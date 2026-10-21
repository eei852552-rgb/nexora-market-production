# NEXORA MARKET — Supabase Auth Security Status

## Verified state

- Project: `nexora-market`
- Project ref: `nbhfdiiehukdtusxksni`
- Project status: `ACTIVE_HEALTHY`
- Organization plan: `free`
- Security Advisor: `auth_leaked_password_protection` remains `WARN`.
- No Auth setting was changed by this task.

## Official Supabase behavior

Supabase documents Leaked Password Protection under the hosted project's Auth settings. It checks passwords against the Have I Been Pwned password corpus and rejects known leaked passwords. Supabase documents the feature as available on the Pro Plan and above.

Official documentation: <https://supabase.com/docs/guides/auth/password-security>

## Why this task cannot enable it automatically

The available Supabase MCP tools can inspect projects, migrations, tables, SQL, logs, and Security Advisor results. They do not expose a hosted Auth-security-setting write operation. The Management API requires a user-authorized Personal Access Token or OAuth token, and this task has no such token available or authorized for use. No credential was requested, exposed, or created.

Supabase's access-control documentation says project Auth configuration updates require an Owner or Administrator-level project permission:

<https://supabase.com/docs/guides/platform/access-control>

## Required manual path

1. If the project remains on Free, move the organization/project to a plan that supports the feature. Supabase documents Pro and above as the requirement.
2. Open the `nexora-market` project in the Supabase Dashboard.
3. Go to **Authentication → Auth settings** or the Email provider's password-security settings.
4. Enable **Leaked Password Protection** and save.
5. Run Security Advisor again and confirm `auth_leaked_password_protection` is no longer reported.

Do not paste a Personal Access Token, password, service-role key, or other secret into the repository or chat. Do not change Auth settings through an unverified API endpoint.
