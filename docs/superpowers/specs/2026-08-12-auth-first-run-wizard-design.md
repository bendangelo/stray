# Stray — Auth & First-Run Wizard

**Date:** 2026-08-12
**Phase:** V1 Sub-Project 1 — Auth & First-Run Wizard
**Status:** Approved

## Purpose

Establish the authentication foundation for Stray: a single-user login system using Rails 8.1's built-in authentication generator, with views customized to the design system. Include a web-based first-run wizard (`/setup`) that creates the first admin account when no users exist, and a CLI wizard (`bin/setup-wizard`) that writes `.env` configuration before first deploy.

This is the foundation for all subsequent V1 sub-projects — every feature (sources, items, feed, interactions) requires an authenticated user.

## Context

The Stray repo has the design foundation in place (Phase 0): Tailwind v4 `@theme` tokens, layout shell (navbar, footer), placeholder homepage, logo, favicon, and Space Grotesk header font. The `ApplicationController` has no auth. There are no models, no auth routes, and `bcrypt` is commented out in the Gemfile.

The project plan (§2, §11) specifies: Rails 8 built-in `has_secure_password` auth (no Devise), single-user first, `bin/setup-wizard` CLI + web-based first-run wizard, all config via `ENV` vars.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Auth system | Rails 8.1 `bin/rails generate authentication` | Complete auth out of the box: User model, SessionsController, PasswordsController, Authentication concern. No Devise dependency. |
| Template engine | ERB (keep scaffold default) | Matches Phase 0 design foundation |
| Views | Customize all generated views to design system | Champagne bg, charcoal text/borders, carrot accents, Space Grotesk headers |
| Password reset | Include (PasswordsController from generator) | Works when SMTP configured; fails gracefully if not. Fallback: `rails console`. |
| First-run web wizard | One-step: create admin account at `/setup` | Simplest viable wizard. Redirects all requests to `/setup` when `User.count.zero?`. |
| CLI wizard | `bin/setup-wizard` writes `.env` only (stateless) | No DB access needed. User runs CLI wizard, starts app, visits `/setup` to create account. |
| AI provider | Optional, defaults to NONE | Everything works without external AI. Zero-shot embedding tagging uses a local model. |
| User model fields | `email`, `username`, `password_digest` | `username` instead of `display_name` per user preference. Email normalized (strip + downcase). |

## Section 1: Auth System (Rails 8 Built-In)

### What `bin/rails generate authentication` provides

- **`User` model**: `email` (unique, normalized), `password_digest`, `has_secure_password`
- **`Session` model**: tracks sessions via `user_id`, `ip_address`, `user_agent`
- **`SessionsController`**: `new` (login form), `create` (login), `destroy` (logout)
- **`PasswordsController`**: `new` (request reset), `create` (send reset email), `edit` (set new password), `update` (save new password)
- **`Authentication` concern**: `before_action :require_authentication`, `resume_session`, helper methods `authenticated?`, `current_user`
- Basic views for all of the above

### Customizations

- All views rewritten to match the champagne/charcoal/carrot design system (Tailwind classes from Phase 0 design foundation)
- Login form uses athens background, charcoal 3px borders, carrot submit button
- Password reset flow styled consistently
- Navigation bar adds login/logout link based on `authenticated?`

### Email delivery

- Password reset requires `ActionMailer` + SMTP. For V1, if SMTP is not configured, the reset email silently fails (logs an error, shows a flash message). The user can reset passwords via `rails console` as a fallback.
- `config/environments/production.rb` SMTP settings read from `ENV` vars (`SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`). All commented out / no-op when `SMTP_HOST` is blank.
- `config/environments/development.rb` sets `action_mailer.default_url_options = { host: "localhost", port: 3000 }` (already present in scaffold) and `action_mailer.raise_delivery_errors = false` (already present).

### `Gemfile` change

Uncomment the `bcrypt` gem:
```ruby
gem "bcrypt", "~> 3.1.7"
```

## Section 2: First-Run Web Wizard

### Behavior

- A `before_action` in `ApplicationController` checks: if `User.count.zero?` and the request is not to `/setup`, redirect to `/setup`
- `SetupController` (inherits from `ApplicationController`, skips `require_authentication`) with a single `new`/`create` flow
- The setup page shows a form: username, email, password, password confirmation
- On submit: creates the first `User` record, redirects to login with a success flash
- Once `User.count > 0`, `/setup` redirects to root (wizard no longer accessible)

### Route

```ruby
resource :setup, only: [:new, :create], controller: "setup"
```

### Guard logic (in `ApplicationController`)

```ruby
before_action :redirect_to_setup_if_needed

private

def redirect_to_setup_if_needed
  return if authenticated? || User.any?
  return if request.path == "/setup"
  redirect_to new_setup_path
end
```

This runs before `require_authentication` (which the Rails 8 generator adds). When no users exist, the setup wizard is the only accessible page. Once the first user is created, normal auth flow takes over.

### Design

- Centered card on champagne background, matching the homepage hero layout
- Stray logo at top (same as homepage)
- Form fields with athens background, charcoal 3px borders, carrot submit button
- Minimal copy: "Welcome to Stray. Create your account to get started."

## Section 3: CLI Wizard (`bin/setup-wizard`)

### Purpose

Runs on the host before first deploy. Interactive CLI prompts that write `.env` from `.env.example`. Idempotent and re-runnable. Never runs inside a container.

### Flow

1. Check if `/.dockerenv` exists — if so, print "This wizard must run on the host, not inside a container" and exit
2. Check if `.env` exists — if so, prompt "Overwrite existing .env?" (default: no, exit)
3. Copy `.env.example` to `.env` if it doesn't exist
4. Prompt for each variable, showing the current/default value:
   - `INSTANCE_NAME` — e.g. "My Stray" (default: "Stray")
   - `INSTANCE_DOMAIN` — e.g. "stray.example.com" (default: localhost)
   - `SECRET_KEY_BASE` — auto-generate via `SecureRandom.hex(64)` if empty
   - `AI_PROVIDER` — NONE / OLLAMA / OPENAI_COMPATIBLE (default: NONE)
   - `AI_PROVIDER_URL` — only if AI_PROVIDER != NONE (e.g. http://localhost:11434 for Ollama)
   - `AI_PROVIDER_API_KEY` — only if AI_PROVIDER == OPENAI_COMPATIBLE
   - `SMTP_HOST` — optional (default: blank, skip)
   - `SMTP_PORT` — optional (default: 587)
   - `SMTP_USERNAME` — optional
   - `SMTP_PASSWORD` — optional (input hidden)
5. Write all values to `.env`
6. Print next steps: "Run `docker compose up -d` or `kamal deploy` to start Stray. Then visit /setup to create your admin account."

### Implementation

- Ruby script (`bin/setup-wizard`), executable (`chmod +x`)
- Uses `Readline` for input (part of stdlib, no gem needed)
- Password inputs use `Readline` with no echo
- Validates email format (for SMTP config if provided), valid AI provider choice
- `SECRET_KEY_BASE` auto-generated via `SecureRandom.hex(64)` if the user accepts the default

### `.env.example`

```
# Stray configuration
# Copy this file to .env and fill in your values, or run bin/setup-wizard

# Instance
INSTANCE_NAME=Stray
INSTANCE_DOMAIN=localhost

# Security
SECRET_KEY_BASE=

# AI provider (NONE, OLLAMA, OPENAI_COMPATIBLE)
# Everything works without AI. NONE = zero-shot embedding tagging only (local model).
# OLLAMA = local Ollama instance for LLM tagging
# OPENAI_COMPATIBLE = any OpenAI-compatible API endpoint
AI_PROVIDER=NONE
AI_PROVIDER_URL=
AI_PROVIDER_API_KEY=

# SMTP (optional — needed for password reset emails)
# Leave blank to skip email. Passwords can be reset via rails console.
SMTP_HOST=
SMTP_PORT=587
SMTP_USERNAME=
SMTP_PASSWORD=
```

### Stateless design

The CLI wizard writes `.env` only — it does NOT create the admin account in the database. Account creation is always handled by the web wizard (`/setup`) on first run. This keeps the CLI wizard stateless (no DB access needed, no Rails boot required).

## Section 4: User Model

### Model

```ruby
class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  normalizes :email, with: ->(e) { e.strip.downcase }
end
```

### Schema

```ruby
create_table "users" do |t|
  t.string :email, null: false
  t.string :password_digest, null: false
  t.string :username
  t.timestamps
end
add_index :users, :email, unique: true
```

Matches the project plan (§3) — `email`, `username` (renamed from `display_name` per user preference), `password_digest`, `created_at`. The `Session` model for session tracking is included by the Rails 8 generator.

### Session model (from generator)

```ruby
create_table "sessions" do |t|
  t.references :user, null: false, foreign_key: true
  t.string :ip_address
  t.string :user_agent
  t.timestamps
end
```

## Section 5: Views & Design Integration

All auth views rewritten from the Rails 8 generator defaults to match the champagne/charcoal/carrot design system.

### Login (`sessions/new.html.erb`)

- Centered card on champagne background, same hero layout as homepage
- Stray logo at top
- Form: email field, password field, "Log in" submit button (carrot orange)
- Fields use athens background, 3px charcoal borders
- "Forgot password?" link below the form → `new_password_path`
- Flash messages styled with cerise for errors, mint for success

### Logout

- Navbar shows "Log out" link when `authenticated?` — styled as a text link, not a button
- No dedicated view — `destroy` action redirects to root with a flash

### Password reset request (`passwords/new.html.erb`)

- Same centered card layout
- Single email field + "Send reset link" button (carrot)
- Flash: "If that email exists, a reset link has been sent."

### Password reset edit (`passwords/edit.html.erb`)

- Same centered card layout
- New password + confirmation fields + "Update password" button (carrot)
- Accessed via token in URL: `/passwords/edit?reset_password_token=...`

### Setup wizard (`setup/new.html.erb`)

- Same centered card layout as login
- Stray logo at top
- Form: username, email, password, password confirmation
- "Create account" submit button (carrot)
- Copy: "Welcome to Stray. Create your account to get started."

### Navbar update (`app/views/layouts/_navbar.html.erb`)

- When `authenticated?`: show username + "Log out" link on the right side
- When not authenticated: show "Log in" link on the right side
- Uses the existing navbar partial from the design foundation, extended with auth-aware content

### Mailer views (`user_mailer`)

- Password reset email — plain text + HTML versions
- HTML version uses the design system colors (champagne background, charcoal text, carrot button link)
- Minimal: "Reset your Stray password" + link to `edit_password_path(token)`

## Section 6: File Inventory

### New files

| File | Purpose |
|---|---|
| `app/models/user.rb` | User model (has_secure_password, email, username) |
| `app/models/session.rb` | Session model (tracks user sessions) |
| `app/controllers/sessions_controller.rb` | Login/logout |
| `app/controllers/passwords_controller.rb` | Password reset (request + edit + update) |
| `app/controllers/setup_controller.rb` | First-run web wizard |
| `app/controllers/concerns/authentication.rb` | Auth concern (require_authentication, current_user, authenticated?) |
| `app/views/sessions/new.html.erb` | Login form |
| `app/views/passwords/new.html.erb` | Request reset form |
| `app/views/passwords/edit.html.erb` | Set new password form |
| `app/views/setup/new.html.erb` | First-run wizard form |
| `app/mailers/user_mailer.rb` | Password reset email |
| `app/views/user_mailer/reset_password.html.erb` | HTML reset email |
| `app/views/user_mailer/reset_password.text.erb` | Plain text reset email |
| `db/migrate/YYYYMMDDHHMMSS_create_users.rb` | Users table migration |
| `db/migrate/YYYYMMDDHHMMSS_create_sessions.rb` | Sessions table migration |
| `bin/setup-wizard` | CLI setup wizard (executable Ruby script) |
| `.env.example` | Template env file with documented variables |
| `test/models/user_test.rb` | User model tests |
| `test/controllers/sessions_controller_test.rb` | Login/logout tests |
| `test/controllers/passwords_controller_test.rb` | Password reset tests |
| `test/controllers/setup_controller_test.rb` | First-run wizard tests |
| `test/mailers/user_mailer_test.rb` | Mailer tests |

### Modified files

| File | Changes |
|---|---|
| `app/controllers/application_controller.rb` | Add `redirect_to_setup_if_needed` before_action, include `Authentication` concern |
| `app/views/layouts/_navbar.html.erb` | Add auth-aware links (login/logout/username) |
| `config/routes.rb` | Add auth routes (resource :session, resource :password, resource :setup) |
| `config/environments/production.rb` | Configure SMTP settings from env vars (conditional on SMTP_HOST being set) |
| `config/environments/development.rb` | Configure mailer for dev (default_url_options already present, raise_delivery_errors already false) |
| `Gemfile` | Uncomment `bcrypt` gem |

### `.gitignore`

No change needed — `.env*` is already in `.gitignore` (line 11).

## Section 7: Testing & Verification

### Model tests (`test/models/user_test.rb`)

- User with valid email + password is valid
- User with duplicate email is invalid
- Email is normalized (strip + downcase)
- User with password < 8 chars is invalid (has_secure_password default)
- User authenticates with correct password, rejects wrong password

### Session controller tests (`test/controllers/sessions_controller_test.rb`)

- GET new (login form) returns 200 when not authenticated
- POST create with valid credentials creates a session and redirects to root
- POST create with invalid credentials re-renders new with flash error
- DELETE destroy logs out and clears session
- Authenticated user accessing new is redirected to root

### Password controller tests (`test/controllers/passwords_controller_test.rb`)

- GET new (request reset form) returns 200
- POST create with existing email enqueues reset email and redirects with flash
- POST create with non-existent email still redirects with flash (don't leak which emails exist)
- GET edit with valid token returns 200 and shows reset form
- GET edit with invalid/expired token redirects with error flash
- PATCH update with valid password updates the user and redirects to login
- PATCH update with mismatched passwords re-renders edit with error

### Setup controller tests (`test/controllers/setup_controller_test.rb`)

- GET new returns 200 when User.count.zero?
- GET new redirects to root when users already exist
- POST create with valid params creates first user and redirects to login
- POST create when users already exist redirects to root (wizard locked)
- Any authenticated request when User.count.zero? redirects to /setup
- Unauthenticated request to a protected route when User.count.zero? redirects to /setup

### Mailer tests (`test/mailers/user_mailer_test.rb`)

- Reset password email is delivered to the user's email
- Reset password email contains the reset link with token

### Verification commands

- `bin/rails test` — all tests pass
- `bin/rubocop` — lint passes
- `bin/brakeman` — security scan passes (auth system, session management, password reset — all common areas for vulnerabilities)
- `bin/rails server` + manual check:
  - With no users: visiting `/` redirects to `/setup`
  - Create admin account via setup wizard
  - Log in with credentials
  - Log out
  - Test "Forgot password" flow (if SMTP configured)

### CI coverage

Existing CI workflow already runs RuboCop, Brakeman, bundler-audit, Minitest, and system tests. No CI changes needed.