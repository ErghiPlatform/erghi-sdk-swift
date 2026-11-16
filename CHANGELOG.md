## Unreleased

- New: `ErghiClient.inbox` (labels, conversation labels, notes, saved replies, `unassignConversation`) and `ErghiClient.contacts` (list, search, get, update, block, unblock, erase, contact notes, notifications, mentionable members) with typed models. Labels, conversation notes and saved replies work against the current platform and need `view_conversations` (writes to labels and saved replies need `manage_inbox_settings`); Workspace API keys cannot hold `view_conversations`, `manage_inbox_settings` or `manage_contacts` (not in the platform's grantable key scopes), so these calls need a signed-in teammate's access token; with an API key they answer 403. Contacts, contact notes, notifications, `@mention` ids on notes and `unassign` require platform PR #256 and answer 404 until it ships. Erasing a contact is permanent. No workspace id is ever passed; it comes from the credential.

- New: `ErghiClient.insights` for Conversation Insights: `summary`, `listConversations` and `exportCSV`, with `InsightFilter`, `InsightSummary` and `InsightPage`. Needs the `view_insights` workspace permission, so use a signed-in Owner or Admin access token; API keys and client-credentials tokens get 403.

## 1.1.0 (2026-11-05)

- Fix: `AuthResource` now talks to the platform's real auth endpoints (`refresh` and `me`
  called paths that do not exist) and maps the auth server's snake_case session, which `login`
  could not decode before.
- New: `verifyEmail`, `forgotPassword`, `resetPassword`, `ChatResource.listConversations` and
  `closeConversation`.
- Fix: `markAsRead` used PUT; the endpoint is POST.
- Fix: the request interceptor no longer overwrites an `Authorization` header already on the
  request.
