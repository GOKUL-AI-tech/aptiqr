// AptiQR — user provisioning (admin, or faculty for students only)
//
// Creates a Supabase Auth user + the matching role row (students /
// faculty / admins) in one call, using the service_role key. This must
// run server-side (Edge Function), never in the Flutter client, because
// only the service role can create auth users on someone else's behalf.
//
// Authorization:
//   - admin callers: can create student, faculty, or admin accounts,
//     into any department.
//   - faculty callers: can ONLY create student accounts (never faculty
//     or admin), and ONLY into their own assigned department — any
//     department_id sent in the request body is ignored and overwritten
//     with the caller's own department_id, fetched server-side from
//     their `faculty` row. This is enforced here, not just in the
//     Flutter UI, because the UI can't be trusted as the only gate on
//     who gets to create accounts.
//   - anyone else (students, unauthenticated): rejected.
//
// Deploy:  supabase functions deploy create-user
// Invoke from Flutter:
//   await supabase.functions.invoke('create-user', body: {...});
//
// Request body:
// {
//   "role": "student" | "faculty" | "admin",
//   "full_name": "...",
//   "email": "...",                 // real email, or synthetic e.g. 22cs101@students.aptiqr.local
//   "phone": "...",                 // optional
//   "password": "...",              // temp password; student/faculty should change it via "Forgot password"
//   // student-only:
//   "register_number": "...",
//   "department_id": "uuid",        // ignored for faculty callers — see above
//   "year": 1,
//   "section": "A",
//   // faculty-only (admin caller only — faculty callers can't create faculty accounts):
//   "faculty_id": "...",
//   "assigned_years": [1,2,3,4],
//   // admin-only (admin caller only — this is how you create the 2nd/3rd
//   // admin login for Technical/Communication once you already have one
//   // Aptitude admin account; see README "Creating the Technical /
//   // Communication admin logins"):
//   "category": "aptitude" | "technical" | "communication"
// }

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

serve(async (req) => {
  try {
    const authHeader = req.headers.get('Authorization') ?? '';
    const callerClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      global: { headers: { Authorization: authHeader } },
    });

    // Verify the caller is authenticated and is either an admin, or a
    // faculty member creating a student account.
    const { data: { user } } = await callerClient.auth.getUser();
    if (!user) {
      return new Response(JSON.stringify({ error: 'Not authenticated' }), { status: 401 });
    }
    const { data: callerProfile } = await callerClient
      .from('profiles')
      .select('role')
      .eq('id', user.id)
      .single();

    const body = await req.json();
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    let facultyDepartmentId: string | null = null;
    if (callerProfile?.role === 'admin') {
      // Full access — falls through below.
    } else if (callerProfile?.role === 'faculty') {
      if (body.role !== 'student') {
        return new Response(
          JSON.stringify({ error: 'Faculty can only create student accounts' }),
          { status: 403 },
        );
      }
      // Look up the caller's own department server-side rather than
      // trusting whatever department_id the request body claims — a
      // faculty member should only ever be able to add students to
      // their own department, no matter what the client sends.
      const { data: callerFaculty } = await admin
        .from('faculty')
        .select('department_id')
        .eq('id', user.id)
        .single();
      if (!callerFaculty?.department_id) {
        return new Response(
          JSON.stringify({ error: 'Your faculty account has no assigned department yet — ask an admin to set one.' }),
          { status: 403 },
        );
      }
      facultyDepartmentId = callerFaculty.department_id;
    } else {
      return new Response(JSON.stringify({ error: 'Not authorized' }), { status: 403 });
    }

    // Validated *before* createUser below, not after — this used to be
    // checked only once we reached the `admins` insert branch, by which
    // point auth.admin.createUser() had already run. An invalid category
    // then left a real, already-created auth user (and the profiles row
    // handle_new_user stamps role='admin' onto) with no matching `admins`
    // row at all: a half-provisioned admin account with no category, so
    // current_admin_category() would return null and every RLS check for
    // that account would silently fail. Checking first means a bad
    // request never creates anything.
    const allowedCategories = ['aptitude', 'technical', 'communication'];
    if (body.role === 'admin' && !allowedCategories.includes(body.category)) {
      return new Response(
        JSON.stringify({ error: `category must be one of ${allowedCategories.join(', ')}` }),
        { status: 400 },
      );
    }

    const { data: created, error: createErr } = await admin.auth.admin.createUser({
      email: body.email,
      password: body.password,
      email_confirm: true,
      user_metadata: { role: body.role, full_name: body.full_name, phone: body.phone },
    });
    if (createErr) throw createErr;

    const newId = created.user!.id;

    // The role-specific insert below can still fail for reasons that
    // can't be checked up front (e.g. a duplicate register_number/
    // faculty_id unique-constraint hit) — without a rollback, that left
    // a real auth user (and the profiles row handle_new_user creates for
    // it) permanently orphaned with no students/faculty/admins row at
    // all: not visible in any of the app's people lists, but still a
    // live login. Deleting the just-created auth user on failure keeps
    // this endpoint atomic from the caller's point of view — either both
    // rows exist, or neither does.
    try {
      if (body.role === 'student') {
        const { error } = await admin.from('students').insert({
          id: newId,
          register_number: body.register_number,
          // facultyDepartmentId is non-null exactly when the caller is
          // faculty (checked above) — overrides anything the client sent.
          department_id: facultyDepartmentId ?? body.department_id,
          year: body.year,
          section: body.section ?? null,
        });
        if (error) throw error;
      } else if (body.role === 'faculty') {
        const { error } = await admin.from('faculty').insert({
          id: newId,
          faculty_id: body.faculty_id,
          department_id: body.department_id ?? null,
          assigned_years: body.assigned_years ?? [1, 2, 3, 4],
        });
        if (error) throw error;
      } else if (body.role === 'admin') {
        // Only an existing admin can reach this branch (faculty callers
        // are rejected above, before body.role is even inspected).
        // category is fixed at creation time — the app itself never lets
        // an admin change which track they manage after the fact (see
        // policies.sql::current_admin_category / functions.sql). Already
        // validated above, before the auth user was created.
        const { error } = await admin.from('admins').insert({
          id: newId,
          category: body.category,
        });
        if (error) throw error;
      }
    } catch (roleInsertErr) {
      await admin.auth.admin.deleteUser(newId);
      throw roleInsertErr;
    }

    return new Response(JSON.stringify({ id: newId }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: (err as Error).message }), { status: 400 });
  }
});
