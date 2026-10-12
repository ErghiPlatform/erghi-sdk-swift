## Unreleased

- Fix: `AuthResource` now talks to the platform's real auth endpoints (`refresh` and `me`
  called paths that do not exist) and maps the auth server's snake_case session, which `login`
  could not decode before.
- New: `verifyEmail`, `forgotPassword`, `resetPassword`, `ChatResource.listConversations` and
  `closeConversation`.
- Fix: `markAsRead` used PUT; the endpoint is POST.
- Fix: the request interceptor no longer overwrites an `Authorization` header already on the
  request.
