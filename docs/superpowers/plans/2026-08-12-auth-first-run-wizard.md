# Auth & First-Run Wizard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Rails 8.1 built-in authentication with custom design-system views, a web-based first-run wizard (`/setup`), and a CLI setup wizard (`bin/setup-wizard`) that writes `.env`.

**Architecture:** Run `bin/rails generate authentication` to scaffold the auth system, then customize: rename `email_address` to `email`, add `username` column, rewrite all views to the champagne/charcoal/carrot design system, add `SetupController` for first-run wizard, add `redirect_to_setup_if_needed` guard to `ApplicationController`, create `bin/setup-wizard` CLI script and `.env.example`.

**Tech Stack:** Rails 8.1, Ruby 4.0.5, bcrypt, has_secure_password, ActionMailer, SQLite, Minitest

**Spec:** `docs/superpowers/specs/2026-08-12-auth-first-run-wizard-design.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `Gemfile` | Modify | Uncomment `bcrypt` gem |
| `app/models/user.rb` | Modify (post-generation) | Rename `email_address` → `email`, add `username` |
| `app/models/session.rb` | Keep (generated) | Session tracking |
| `app/models/current.rb` | Keep (generated) | CurrentAttributes for current session/user |
| `app/controllers/concerns/authentication.rb` | Keep (generated) | Auth concern |
| `app/controllers/sessions_controller.rb` | Modify (post-generation) | Rename `email_address` → `email` param |
| `app/controllers/passwords_controller.rb` | Modify (post-generation) | Rename `email_address` → `email` param |
| `app/controllers/application_controller.rb` | Modify | Add `redirect_to_setup_if_needed` before_action |
| `app/controllers/setup_controller.rb` | Create | First-run web wizard |
| `app/mailers/passwords_mailer.rb` | Modify (post-generation) | Rename `email_address` → `email` |
| `app/views/sessions/new.html.erb` | Modify (post-generation) | Restyle to design system |
| `app/views/passwords/new.html.erb` | Modify (post-generation) | Restyle to design system |
| `app/views/passwords/edit.html.erb` | Modify (post-generation) | Restyle to design system |
| `app/views/passwords_mailer/reset.html.erb` | Modify (post-generation) | Restyle to design system |
| `app/views/passwords_mailer/reset.text.erb` | Keep (generated) | Plain text reset email |
| `app/views/setup/new.html.erb` | Create | First-run wizard form |
| `app/views/layouts/_navbar.html.erb` | Modify | Add auth-aware login/logout/username links |
| `app/views/layouts/application.html.erb` | Modify | Add flash message rendering |
| `config/routes.rb` | Modify (post-generation) | Add `resource :setup` |
| `config/environments/production.rb` | Modify | Configure SMTP from env vars |
| `db/migrate/*_create_users.rb` | Modify (post-generation) | Rename `email_address` → `email`, add `username` |
| `db/migrate/*_create_sessions.rb` | Keep (generated) | Sessions table |
| `test/fixtures/users.yml` | Modify (post-generation) | Rename `email_address` → `email`, add `username` |
| `test/models/user_test.rb` | Modify (post-generation) | Add username + email tests |
| `test/controllers/sessions_controller_test.rb` | Modify (post-generation) | Rename `email_address` → `email` |
| `test/controllers/passwords_controller_test.rb` | Modify (post-generation) | Rename `email_address` → `email` |
| `test/controllers/setup_controller_test.rb` | Create | First-run wizard tests |
| `test/mailers/previews/passwords_mailer_preview.rb` | Keep (generated) | Mailer preview |
| `test/test_helpers/session_test_helper.rb` | Keep (generated) | Sign-in test helper |
| `bin/setup-wizard` | Create | CLI setup wizard |
| `.env.example` | Create | Template env file |

---

## Task 1: Run Authentication Generator

**Files:**
- Modify: `Gemfile` (bcrypt uncommented by generator)
- Create: `app/models/user.rb`, `app/models/session.rb`, `app/models/current.rb`
- Create: `app/controllers/sessions_controller.rb`, `app/controllers/passwords_controller.rb`, `app/controllers/concerns/authentication.rb`
- Create: `app/mailers/passwords_mailer.rb`
- Create: `app/views/sessions/new.html.erb`, `app/views/passwords/new.html.erb`, `app/views/passwords/edit.html.erb`
- Create: `app/views/passwords_mailer/reset.html.erb`, `app/views/passwords_mailer/reset.text.erb`
- Create: `db/migrate/*_create_users.rb`, `db/migrate/*_create_sessions.rb`
- Create: `test/fixtures/users.yml`, `test/models/user_test.rb`, `test/controllers/sessions_controller_test.rb`, `test/controllers/passwords_controller_test.rb`
- Create: `test/test_helpers/session_test_helper.rb`, `test/mailers/previews/passwords_mailer_preview.rb`
- Modify: `app/controllers/application_controller.rb` (adds `include Authentication`)
- Modify: `config/routes.rb` (adds session/password routes)
- Modify: `test/test_helper.rb` (adds session test helper require)

- [ ] **Step 1: Run the Rails 8.1 authentication generator**

```bash
bin/rails generate authentication
```

Expected output: creates all the files listed above, modifies `Gemfile` (uncomments bcrypt), runs `bundle install`, creates migrations. The generator uses `email_address` (not `email`) — we'll rename in later tasks.

- [ ] **Step 2: Run the generated tests to verify the baseline works**

```bash
bin/rails db:migrate
bin/rails test
```

Expected: all generated tests pass. This confirms the auth system works before we customize it.

- [ ] **Step 3: Commit the generated auth scaffold**

```bash
git add -A
git commit -m "feat: generate Rails 8.1 authentication scaffold

User model (has_secure_password, email_address), Session model,
SessionsController (login/logout), PasswordsController (reset),
PasswordsMailer, Authentication concern, Current model.
Generated tests and fixtures included."
```

---

## Task 2: Rename `email_address` to `email`, Add `username`, and Add `current_user` Helper

**Files:**
- Modify: `db/migrate/*_create_users.rb`
- Modify: `app/models/user.rb`
- Modify: `app/controllers/concerns/authentication.rb`
- Modify: `app/controllers/sessions_controller.rb`
- Modify: `app/controllers/passwords_controller.rb`
- Modify: `app/mailers/passwords_mailer.rb`
- Modify: `test/fixtures/users.yml`
- Modify: `test/models/user_test.rb`
- Modify: `test/controllers/sessions_controller_test.rb`
- Modify: `test/controllers/passwords_controller_test.rb`

The generator uses `email_address` throughout. The spec requires `email` and a new `username` column. Since the migration hasn't been run in production, we modify the migration file directly rather than creating a new migration.

- [ ] **Step 1: Modify the users migration**

Open `db/migrate/*_create_users.rb` (the timestamp-prefixed filename). Replace its contents with:

```ruby
class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :password_digest, null: false
      t.string :username

      t.timestamps
    end
    add_index :users, :email, unique: true
  end
end
```

- [ ] **Step 2: Drop and recreate the database (migration changed before any production deploy)**

```bash
bin/rails db:drop db:create db:migrate
```

Expected: database recreated with `email` column (not `email_address`) and `username` column.

- [ ] **Step 3: Update the User model**

Replace `app/models/user.rb` with:

```ruby
class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  normalizes :email, with: ->(e) { e.strip.downcase }

  validates :email, presence: true, uniqueness: true
  validates :username, presence: true
end
```

- [ ] **Step 4: Add `current_user` helper method to Authentication concern**

The generated `Authentication` concern has `helper_method :authenticated?` but not `current_user`. We need it in the navbar view. In `app/controllers/concerns/authentication.rb`, add `current_user` to the `helper_method` line and define the method.

Change line 6:

From:
```ruby
    helper_method :authenticated?
```

To:
```ruby
    helper_method :authenticated?, :current_user
```

And add the `current_user` method in the `private` section, after the `authenticated?` method:

```ruby
    def current_user
      resume_session&.user
    end
```

The full `private` section should now start with:

```ruby
  private
    def authenticated?
      resume_session
    end

    def current_user
      resume_session&.user
    end

    def require_authentication
      resume_session || request_authentication
    end
```

- [ ] **Step 5: Update test fixtures**

Replace `test/fixtures/users.yml` with:

```yaml
<% password_digest = BCrypt::Password.create("password") %>

one:
  email: one@example.com
  username: one
  password_digest: <%= password_digest %>

two:
  email: two@example.com
  username: two
  password_digest: <%= password_digest %>
```

- [ ] **Step 6: Update the User model test**

Replace `test/models/user_test.rb` with:

```ruby
require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email" do
    user = User.new(email: " DOWNCASED@EXAMPLE.COM ", username: "test", password: "password", password_confirmation: "password")
    assert_equal("downcased@example.com", user.email)
  end

  test "valid user with email, username, and password" do
    user = User.new(email: "test@example.com", username: "test", password: "password", password_confirmation: "password")
    assert user.valid?
  end

  test "invalid with duplicate email" do
    User.create!(email: "dup@example.com", username: "dup1", password: "password", password_confirmation: "password")
    user = User.new(email: "dup@example.com", username: "dup2", password: "password", password_confirmation: "password")
    assert_not user.valid?
  end

  test "invalid without username" do
    user = User.new(email: "nousername@example.com", password: "password", password_confirmation: "password")
    assert_not user.valid?
  end

  test "invalid with short password" do
    user = User.new(email: "short@example.com", username: "short", password: "short", password_confirmation: "short")
    assert_not user.valid?
  end
end
```

- [ ] **Step 7: Update SessionsController to use `email`**

In `app/controllers/sessions_controller.rb`, change line 9:

From:
```ruby
    if user = User.authenticate_by(params.permit(:email_address, :password))
```

To:
```ruby
    if user = User.authenticate_by(params.permit(:email, :password))
```

- [ ] **Step 8: Update PasswordsController to use `email`**

In `app/controllers/passwords_controller.rb`, change line 10:

From:
```ruby
    if user = User.find_by(email_address: params[:email_address])
```

To:
```ruby
    if user = User.find_by(email: params[:email])
```

- [ ] **Step 9: Update PasswordsMailer to use `email`**

In `app/mailers/passwords_mailer.rb`, change line 4:

From:
```ruby
    mail subject: "Reset your password", to: user.email_address
```

To:
```ruby
    mail subject: "Reset your password", to: user.email
```

- [ ] **Step 10: Update sessions controller test to use `email`**

In `test/controllers/sessions_controller_test.rb`, change line 12:

From:
```ruby
    post session_path, params: { email_address: @user.email_address, password: "password" }
```

To:
```ruby
    post session_path, params: { email: @user.email, password: "password" }
```

And line 19:

From:
```ruby
    post session_path, params: { email_address: @user.email_address, password: "wrong" }
```

To:
```ruby
    post session_path, params: { email: @user.email, password: "wrong" }
```

- [ ] **Step 11: Update passwords controller test to use `email`**

In `test/controllers/passwords_controller_test.rb`, change line 12:

From:
```ruby
    post passwords_path, params: { email_address: @user.email_address }
```

To:
```ruby
    post passwords_path, params: { email: @user.email }
```

- [ ] **Step 12: Run tests to verify the rename works**

```bash
bin/rails test
```

Expected: all tests pass with the renamed `email` field and new `username` field.

- [ ] **Step 13: Commit**

```bash
git add -A
git commit -m "refactor: rename email_address to email, add username and current_user helper

Rename email_address to email throughout (model, controllers, mailer,
tests, fixtures). Add username column with presence validation. Add
current_user helper method to Authentication concern for view access."
```

---

## Task 3: Add the Setup Controller (First-Run Web Wizard)

**Files:**
- Create: `app/controllers/setup_controller.rb`
- Create: `app/views/setup/new.html.erb`
- Create: `test/controllers/setup_controller_test.rb`
- Modify: `app/controllers/application_controller.rb`
- Modify: `config/routes.rb`

- [ ] **Step 1: Write the failing test**

Create `test/controllers/setup_controller_test.rb`:

```ruby
require "test_helper"

class SetupControllerTest < ActionDispatch::IntegrationTest
  setup do
    User.delete_all
  end

  test "GET new returns 200 when no users exist" do
    get new_setup_path
    assert_response :success
  end

  test "POST create with valid params creates first user" do
    assert_difference("User.count", 1) do
      post setup_path, params: {
        user: {
          username: "admin",
          email: "admin@example.com",
          password: "password",
          password_confirmation: "password"
        }
      }
    end
    assert_redirected_to new_session_path
  end

  test "POST create when users exist redirects to root" do
    User.create!(username: "existing", email: "existing@example.com", password: "password", password_confirmation: "password")
    post setup_path, params: {
      user: {
        username: "admin",
        email: "admin@example.com",
        password: "password",
        password_confirmation: "password"
      }
    }
    assert_redirected_to root_path
  end

  test "GET new redirects to root when users exist" do
    User.create!(username: "existing", email: "existing@example.com", password: "password", password_confirmation: "password")
    get new_setup_path
    assert_redirected_to root_path
  end

  test "unauthenticated request redirects to setup when no users exist" do
    get root_path
    assert_redirected_to new_setup_path
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bin/rails test test/controllers/setup_controller_test.rb
```

Expected: FAIL with `No route matches [GET] "/setup"` — because the controller and routes don't exist yet.

- [ ] **Step 3: Create the SetupController**

Create `app/controllers/setup_controller.rb`:

```ruby
class SetupController < ApplicationController
  allow_unauthenticated_access
  before_action :redirect_if_users_exist

  def new
    @user = User.new
  end

  def create
    if User.any?
      redirect_to root_path and return
    end

    @user = User.new(setup_params)
    if @user.save
      redirect_to new_session_path, notice: "Account created. Please sign in."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def redirect_if_users_exist
    redirect_to root_path if User.any?
  end

  def setup_params
    params.require(:user).permit(:username, :email, :password, :password_confirmation)
  end
end
```

- [ ] **Step 4: Add the setup route**

In `config/routes.rb`, add before the `root` line:

```ruby
  resource :setup, only: [:new, :create], controller: "setup"
```

The full `config/routes.rb` should now be:

```ruby
Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resource :setup, only: [:new, :create], controller: "setup"
  get "up" => "rails/health#show", as: :rails_health_check

  root "pages#index"
  get "privacy_and_terms", to: "pages#privacy_and_terms"
end
```

- [ ] **Step 5: Add the setup redirect guard to ApplicationController**

In `app/controllers/application_controller.rb`, add the `redirect_to_setup_if_needed` before_action. The full file should be:

```ruby
class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :redirect_to_setup_if_needed

  private

  def redirect_to_setup_if_needed
    return if authenticated? || User.any?
    return if request.path == new_setup_path
    redirect_to new_setup_path
  end
end
```

- [ ] **Step 6: Create the setup wizard view**

Create `app/views/setup/new.html.erb`:

```erb
<main class="flex flex-col items-center justify-center mt-[20vh] px-5">
  <%= image_tag "stray-logo.svg", alt: "Stray Logo", class: "lg:w-4/12 md:w-5/12 w-6/12 mb-8" %>

  <div class="w-full max-w-md">
    <h1 class="font-display text-2xl font-bold text-charcoal text-center mb-2">Welcome to Stray</h1>
    <p class="text-sm text-charcoal text-center mb-6">Create your account to get started.</p>

    <% if alert = flash[:alert] %>
      <div class="mb-4 px-4 py-3 border-3 border-cerise text-cerise text-sm" id="alert"><%= alert %></div>
    <% end %>

    <% if notice = flash[:notice] %>
      <div class="mb-4 px-4 py-3 border-3 border-mint-500 text-mint-700 text-sm" id="notice"><%= notice %></div>
    <% end %>

    <%= form_with model: @user, url: setup_path, class: "space-y-4" do |form| %>
      <div>
        <%= form.text_field :username, required: true, autofocus: true, autocomplete: "username", placeholder: "Username", class: "w-full h-12 px-3 bg-athens-400 border-3 border-charcoal rounded-md text-charcoal placeholder:text-charcoal-300 focus:outline-none" %>
      </div>

      <div>
        <%= form.email_field :email, required: true, autocomplete: "email", placeholder: "Email", class: "w-full h-12 px-3 bg-athens-400 border-3 border-charcoal rounded-md text-charcoal placeholder:text-charcoal-300 focus:outline-none" %>
      </div>

      <div>
        <%= form.password_field :password, required: true, autocomplete: "new-password", placeholder: "Password", maxlength: 72, class: "w-full h-12 px-3 bg-athens-400 border-3 border-charcoal rounded-md text-charcoal placeholder:text-charcoal-300 focus:outline-none" %>
      </div>

      <div>
        <%= form.password_field :password_confirmation, required: true, autocomplete: "new-password", placeholder: "Confirm password", maxlength: 72, class: "w-full h-12 px-3 bg-athens-400 border-3 border-charcoal rounded-md text-charcoal placeholder:text-charcoal-300 focus:outline-none" %>
      </div>

      <div>
        <%= form.submit "Create account", class: "w-full h-12 bg-carrot-500 hover:bg-carrot-600 text-white font-medium rounded-md cursor-pointer border-3 border-charcoal" %>
      </div>
    <% end %>
  </div>
</main>
```

- [ ] **Step 7: Run tests to verify they pass**

```bash
bin/rails test test/controllers/setup_controller_test.rb
```

Expected: all 5 setup controller tests pass.

- [ ] **Step 8: Run the full test suite**

```bash
bin/rails test
```

Expected: all tests pass (setup tests + existing auth tests). Note: the existing session/password tests use `User.take` from fixtures — they will still pass because fixtures create users, and the `redirect_to_setup_if_needed` guard checks `User.any?` which will be true in the test environment with fixtures loaded.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: add first-run setup wizard at /setup

SetupController creates the first admin account when User.count.zero?.
ApplicationController redirects all requests to /setup when no users
exist. Once the first user is created, the wizard is locked.
Custom design system view with champagne bg, charcoal borders,
carrot submit button."
```

---

## Task 4: Restyle Login View to Design System

**Files:**
- Modify: `app/views/sessions/new.html.erb`

- [ ] **Step 1: Replace the login view**

Replace `app/views/sessions/new.html.erb` with:

```erb
<main class="flex flex-col items-center justify-center mt-[20vh] px-5">
  <%= image_tag "stray-logo.svg", alt: "Stray Logo", class: "lg:w-4/12 md:w-5/12 w-6/12 mb-8" %>

  <div class="w-full max-w-md">
    <h1 class="font-display text-2xl font-bold text-charcoal text-center mb-6">Sign in</h1>

    <% if alert = flash[:alert] %>
      <div class="mb-4 px-4 py-3 border-3 border-cerise text-cerise text-sm" id="alert"><%= alert %></div>
    <% end %>

    <% if notice = flash[:notice] %>
      <div class="mb-4 px-4 py-3 border-3 border-mint-500 text-mint-700 text-sm" id="notice"><%= notice %></div>
    <% end %>

    <%= form_with url: session_url, class: "space-y-4" do |form| %>
      <div>
        <%= form.email_field :email, required: true, autofocus: true, autocomplete: "username", placeholder: "Email", value: params[:email], class: "w-full h-12 px-3 bg-athens-400 border-3 border-charcoal rounded-md text-charcoal placeholder:text-charcoal-300 focus:outline-none" %>
      </div>

      <div>
        <%= form.password_field :password, required: true, autocomplete: "current-password", placeholder: "Password", maxlength: 72, class: "w-full h-12 px-3 bg-athens-400 border-3 border-charcoal rounded-md text-charcoal placeholder:text-charcoal-300 focus:outline-none" %>
      </div>

      <div>
        <%= form.submit "Sign in", class: "w-full h-12 bg-carrot-500 hover:bg-carrot-600 text-white font-medium rounded-md cursor-pointer border-3 border-charcoal" %>
      </div>

      <div class="text-center">
        <%= link_to "Forgot password?", new_password_path, class: "text-sm text-charcoal underline hover:no-underline" %>
      </div>
    <% end %>
  </div>
</main>
```

- [ ] **Step 2: Run tests to verify nothing is broken**

```bash
bin/rails test test/controllers/sessions_controller_test.rb
```

Expected: all session controller tests pass.

- [ ] **Step 3: Commit**

```bash
git add app/views/sessions/new.html.erb
git commit -m "feat: restyle login view to design system

Champagne bg, centered card, Stray logo, athens input fields with
charcoal 3px borders, carrot submit button, cerise error flash,
mint success flash."
```

---

## Task 5: Restyle Password Reset Views to Design System

**Files:**
- Modify: `app/views/passwords/new.html.erb`
- Modify: `app/views/passwords/edit.html.erb`

- [ ] **Step 1: Replace the password reset request view**

Replace `app/views/passwords/new.html.erb` with:

```erb
<main class="flex flex-col items-center justify-center mt-[20vh] px-5">
  <%= image_tag "stray-logo.svg", alt: "Stray Logo", class: "lg:w-4/12 md:w-5/12 w-6/12 mb-8" %>

  <div class="w-full max-w-md">
    <h1 class="font-display text-2xl font-bold text-charcoal text-center mb-6">Forgot your password?</h1>

    <% if alert = flash[:alert] %>
      <div class="mb-4 px-4 py-3 border-3 border-cerise text-cerise text-sm" id="alert"><%= alert %></div>
    <% end %>

    <%= form_with url: passwords_path, class: "space-y-4" do |form| %>
      <div>
        <%= form.email_field :email, required: true, autofocus: true, autocomplete: "username", placeholder: "Email", value: params[:email], class: "w-full h-12 px-3 bg-athens-400 border-3 border-charcoal rounded-md text-charcoal placeholder:text-charcoal-300 focus:outline-none" %>
      </div>

      <div>
        <%= form.submit "Send reset instructions", class: "w-full h-12 bg-carrot-500 hover:bg-carrot-600 text-white font-medium rounded-md cursor-pointer border-3 border-charcoal" %>
      </div>
    <% end %>
  </div>
</main>
```

- [ ] **Step 2: Replace the password reset edit view**

Replace `app/views/passwords/edit.html.erb` with:

```erb
<main class="flex flex-col items-center justify-center mt-[20vh] px-5">
  <%= image_tag "stray-logo.svg", alt: "Stray Logo", class: "lg:w-4/12 md:w-5/12 w-6/12 mb-8" %>

  <div class="w-full max-w-md">
    <h1 class="font-display text-2xl font-bold text-charcoal text-center mb-6">Update your password</h1>

    <% if alert = flash[:alert] %>
      <div class="mb-4 px-4 py-3 border-3 border-cerise text-cerise text-sm" id="alert"><%= alert %></div>
    <% end %>

    <%= form_with url: password_path(params[:token]), method: :put, class: "space-y-4" do |form| %>
      <div>
        <%= form.password_field :password, required: true, autocomplete: "new-password", placeholder: "New password", maxlength: 72, class: "w-full h-12 px-3 bg-athens-400 border-3 border-charcoal rounded-md text-charcoal placeholder:text-charcoal-300 focus:outline-none" %>
      </div>

      <div>
        <%= form.password_field :password_confirmation, required: true, autocomplete: "new-password", placeholder: "Confirm new password", maxlength: 72, class: "w-full h-12 px-3 bg-athens-400 border-3 border-charcoal rounded-md text-charcoal placeholder:text-charcoal-300 focus:outline-none" %>
      </div>

      <div>
        <%= form.submit "Update password", class: "w-full h-12 bg-carrot-500 hover:bg-carrot-600 text-white font-medium rounded-md cursor-pointer border-3 border-charcoal" %>
      </div>
    <% end %>
  </div>
</main>
```

- [ ] **Step 3: Run tests to verify nothing is broken**

```bash
bin/rails test test/controllers/passwords_controller_test.rb
```

Expected: all password controller tests pass.

- [ ] **Step 4: Commit**

```bash
git add app/views/passwords/
git commit -m "feat: restyle password reset views to design system

Both request (new) and edit views use centered card layout with
Stray logo, athens inputs, charcoal borders, carrot submit button.
Matches login view styling."
```

---

## Task 6: Restyle Password Reset Mailer to Design System

**Files:**
- Modify: `app/views/passwords_mailer/reset.html.erb`

- [ ] **Step 1: Replace the HTML mailer view**

Replace `app/views/passwords_mailer/reset.html.erb` with:

```erb
<div style="background-color: #F8F2E8; padding: 40px; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; color: #2A2A2A;">
  <div style="max-width: 480px; margin: 0 auto;">
    <h1 style="font-size: 24px; font-weight: bold; margin-bottom: 16px;">Reset your Stray password</h1>

    <p style="margin-bottom: 24px;">
      You can reset your password by clicking the link below:
    </p>

    <p style="margin-bottom: 24px;">
      <%= link_to "Reset password", edit_password_url(@user.password_reset_token), style: "display: inline-block; padding: 12px 24px; background-color: #FF8E3C; color: #FFFFFF; text-decoration: none; border-radius: 6px; font-weight: 500;" %>
    </p>

    <p style="font-size: 14px; color: #535353;">
      This link will expire in <%= distance_of_time_in_words(0, @user.password_reset_token_expires_in) %>.
    </p>

    <p style="font-size: 14px; color: #535353; margin-top: 24px;">
      If you didn't request a password reset, you can safely ignore this email.
    </p>
  </div>
</div>
```

- [ ] **Step 2: Run tests to verify nothing is broken**

```bash
bin/rails test
```

Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add app/views/passwords_mailer/reset.html.erb
git commit -m "feat: restyle password reset email to design system

HTML email uses champagne bg, charcoal text, carrot button link.
Inline styles for email client compatibility."
```

---

## Task 7: Update Navbar with Auth-Aware Links

**Files:**
- Modify: `app/views/layouts/_navbar.html.erb`

- [ ] **Step 1: Replace the navbar partial**

Replace `app/views/layouts/_navbar.html.erb` with:

```erb
<nav class="pb-2 md:pt-2 md:pl-2 pt-1 border-b-3 border-charcoal">
  <div class="flex pl-2 mx-auto md:pl-4 lg:pl-16 lg:ml-2 items-center justify-between">
    <div class="flex items-center lg:mr-4 md:mr-2 mr-1">
      <%= link_to root_path, tabindex: "-1" do %>
        <%= image_tag "stray-logo.svg", alt: "Stray Logo", class: "w-0 md:w-20 lg:w-28" %>
        <span class="hidden">Stray</span>
      <% end %>
    </div>

    <div class="flex items-center gap-4 pr-4 text-sm">
      <% if authenticated? %>
        <span class="text-charcoal"><%= current_user.username %></span>
        <%= button_to "Log out", session_path, method: :delete, class: "text-charcoal hover:text-carrot-600 underline cursor-pointer bg-transparent border-none" %>
      <% else %>
        <%= link_to "Log in", new_session_path, class: "text-charcoal hover:text-carrot-600 underline" %>
      <% end %>
    </div>
  </div>
</nav>
```

- [ ] **Step 2: Run tests to verify nothing is broken**

```bash
bin/rails test
```

Expected: all tests pass. The navbar now shows auth-aware links.

- [ ] **Step 3: Commit**

```bash
git add app/views/layouts/_navbar.html.erb
git commit -m "feat: add auth-aware links to navbar

Show username + log out button when authenticated.
Show log in link when not authenticated."
```

---

## Task 8: Add Flash Messages to Layout

**Files:**
- Modify: `app/views/layouts/application.html.erb`

- [ ] **Step 1: Add flash rendering above the yield**

In `app/views/layouts/application.html.erb`, the current `<body>` section is:

```erb
  <body class="bg-champagne">
    <%= render "layouts/navbar" %>
    <main>
      <%= yield %>
    </main>
    <%= render "layouts/footer" %>
  </body>
```

Replace it with:

```erb
  <body class="bg-champagne">
    <%= render "layouts/navbar" %>
    <main>
      <% if flash[:alert] %>
        <div class="mx-auto max-w-md mt-4 px-4 py-3 border-3 border-cerise text-cerise text-sm"><%= flash[:alert] %></div>
      <% end %>
      <% if flash[:notice] %>
        <div class="mx-auto max-w-md mt-4 px-4 py-3 border-3 border-mint-500 text-mint-700 text-sm"><%= flash[:notice] %></div>
      <% end %>
      <%= yield %>
    </main>
    <%= render "layouts/footer" %>
  </body>
```

- [ ] **Step 2: Run tests to verify nothing is broken**

```bash
bin/rails test
```

Expected: all tests pass. Flash messages now render in the layout (the individual views also have their own flash rendering — this is intentional belt-and-suspenders for views that don't render flash themselves).

- [ ] **Step 3: Commit**

```bash
git add app/views/layouts/application.html.erb
git commit -m "feat: add flash message rendering to layout

Alert messages styled with cerise border, notice with mint border.
Rendered above yield so all pages show flash consistently."
```

---

## Task 9: Create `.env.example` and `bin/setup-wizard`

**Files:**
- Create: `.env.example`
- Create: `bin/setup-wizard`

- [ ] **Step 1: Create `.env.example`**

Create `.env.example`:

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

# SMTP (optional - needed for password reset emails)
# Leave blank to skip email. Passwords can be reset via rails console.
SMTP_HOST=
SMTP_PORT=587
SMTP_USERNAME=
SMTP_PASSWORD=
```

- [ ] **Step 2: Create the CLI setup wizard**

Create `bin/setup-wizard`:

```ruby
#!/usr/bin/env ruby
require "readline"
require "securerandom"
require "fileutils"

CONTAINER_MARKER = "/.dockerenv"
ENV_EXAMPLE = File.expand_path("../.env.example", __dir__)
ENV_FILE = File.expand_path("../.env", __dir__)

if File.exist?(CONTAINER_MARKER)
  abort "This wizard must run on the host, not inside a container."
end

if File.exist?(ENV_FILE)
  print ".env already exists. Overwrite? [y/N]: "
  response = $stdin.gets.chomp.downcase
  exit 0 unless response == "y"
end

unless File.exist?(ENV_EXAMPLE)
  abort ".env.example not found. Are you running this from the project root?"
end

FileUtils.cp(ENV_EXAMPLE, ENV_FILE) unless File.exist?(ENV_FILE)
env_content = File.read(ENV_FILE)

def prompt(message, default: nil, echo: true)
  suffix = default ? " [#{default}]: " : ": "
  if echo
    Readline.readline("#{message}#{suffix}", false) || ""
  else
    print "#{message}#{suffix}"
    input = $stdin.noecho(&:gets).chomp
    puts
    input
  end
end

def update_env(content, key, value)
  if value.to_s.empty?
    content
  else
    content.gsub(/^#{key}=.*$/, "#{key}=#{value}")
  end
end

puts "Stray setup wizard"
puts "=" * 40
puts

# Instance name
value = prompt("Instance name", default: "Stray")
env_content = update_env(env_content, "INSTANCE_NAME", value.empty? ? "Stray" : value)

# Instance domain
value = prompt("Instance domain", default: "localhost")
env_content = update_env(env_content, "INSTANCE_DOMAIN", value.empty? ? "localhost" : value)

# Secret key base
print "Generate SECRET_KEY_BASE automatically? [Y/n]: "
response = $stdin.gets.chomp.downcase
if response != "n"
  secret = SecureRandom.hex(64)
  env_content = update_env(env_content, "SECRET_KEY_BASE", secret)
  puts "Generated SECRET_KEY_BASE (128 hex chars)"
else
  value = prompt("SECRET_KEY_BASE", echo: false)
  env_content = update_env(env_content, "SECRET_KEY_BASE", value)
end

# AI provider
puts
puts "AI provider options: NONE, OLLAMA, OPENAI_COMPATIBLE"
puts "  NONE = zero-shot embedding tagging only (local model, no external AI)"
puts "  OLLAMA = local Ollama instance for LLM tagging"
puts "  OPENAI_COMPATIBLE = any OpenAI-compatible API endpoint"
value = prompt("AI provider", default: "NONE")
provider = value.empty? ? "NONE" : value.upcase
until %w[NONE OLLAMA OPENAI_COMPATIBLE].include?(provider)
  value = prompt("AI provider (NONE, OLLAMA, OPENAI_COMPATIBLE)", default: "NONE")
  provider = value.empty? ? "NONE" : value.upcase
end
env_content = update_env(env_content, "AI_PROVIDER", provider)

if provider != "NONE"
  value = prompt("AI provider URL", default: provider == "OLLAMA" ? "http://localhost:11434" : nil)
  env_content = update_env(env_content, "AI_PROVIDER_URL", value)

  if provider == "OPENAI_COMPATIBLE"
    value = prompt("AI provider API key", echo: false)
    env_content = update_env(env_content, "AI_PROVIDER_API_KEY", value)
  end
end

# SMTP
puts
puts "SMTP (optional - needed for password reset emails)"
puts "Leave blank to skip. Passwords can be reset via rails console."
smtp_host = prompt("SMTP host", default: "")

unless smtp_host.empty?
  env_content = update_env(env_content, "SMTP_HOST", smtp_host)
  value = prompt("SMTP port", default: "587")
  env_content = update_env(env_content, "SMTP_PORT", value)
  value = prompt("SMTP username", default: "")
  env_content = update_env(env_content, "SMTP_USERNAME", value)
  value = prompt("SMTP password", echo: false)
  env_content = update_env(env_content, "SMTP_PASSWORD", value)
else
  puts "Skipping SMTP configuration."
end

File.write(ENV_FILE, env_content)
puts
puts "=" * 40
puts ".env written successfully."
puts
puts "Next steps:"
puts "  1. Run: docker compose up -d  (or: kamal deploy)"
puts "  2. Visit /setup to create your admin account"
puts "  3. Log in and start using Stray"
```

- [ ] **Step 3: Make the script executable**

```bash
chmod +x bin/setup-wizard
```

- [ ] **Step 4: Verify the script runs**

```bash
echo "n" | bin/setup-wizard
```

Expected: script prints ".env already exists" message and exits (or if no .env, runs through the prompts). Verify it doesn't crash. You may need to pipe input or Ctrl+C after confirming it starts.

- [ ] **Step 5: Commit**

```bash
git add .env.example bin/setup-wizard
git commit -m "feat: add .env.example and bin/setup-wizard CLI

.env.example documents all config variables with defaults.
bin/setup-wizard is an interactive CLI that writes .env from
.env.example. Stateless - no DB access needed. Checks for
/.dockerenv to prevent running inside containers. Validates
AI provider choice. Auto-generates SECRET_KEY_BASE."
```

---

## Task 10: Configure SMTP in Production from Env Vars

**Files:**
- Modify: `config/environments/production.rb`

- [ ] **Step 1: Add conditional SMTP configuration**

In `config/environments/production.rb`, find the commented-out SMTP settings block (lines 63-70):

```ruby
  # Specify outgoing SMTP server. Remember to add smtp/* credentials via bin/rails credentials:edit.
  # config.action_mailer.smtp_settings = {
  #   user_name: Rails.application.credentials.dig(:smtp, :user_name),
  #   password: Rails.application.credentials.dig(:smtp, :password),
  #   address: "smtp.example.com",
  #   port: 587,
  #   authentication: :plain
  # }
```

Replace with:

```ruby
  # Configure SMTP from env vars (optional - needed for password reset emails)
  if ENV["SMTP_HOST"].present?
    config.action_mailer.smtp_settings = {
      address: ENV["SMTP_HOST"],
      port: ENV.fetch("SMTP_PORT", 587),
      user_name: ENV["SMTP_USERNAME"],
      password: ENV["SMTP_PASSWORD"],
      authentication: :plain,
      enable_starttls_auto: true
    }
    config.action_mailer.raise_delivery_errors = true
  end

  config.action_mailer.default_url_options = { host: ENV.fetch("INSTANCE_DOMAIN", "localhost") }
```

Also find and remove/replace the existing `config.action_mailer.default_url_options` line (line 61):

```ruby
  config.action_mailer.default_url_options = { host: "example.com" }
```

Replace it with nothing (it's now handled by the new line above that reads from `INSTANCE_DOMAIN`).

- [ ] **Step 2: Run tests to verify nothing is broken**

```bash
bin/rails test
```

Expected: all tests pass. The production config change doesn't affect test environment.

- [ ] **Step 3: Commit**

```bash
git add config/environments/production.rb
git commit -m "feat: configure SMTP from env vars in production

Conditional SMTP config - only activates when SMTP_HOST is set.
Default URL options read from INSTANCE_DOMAIN env var.
Enables password reset emails when SMTP is configured."
```

---

## Task 11: Lint and Security Verification

**Files:**
- No file changes - verification only

- [ ] **Step 1: Run RuboCop**

```bash
bin/rubocop
```

Expected: no offenses. If offenses are found, fix them before proceeding.

- [ ] **Step 2: Run Brakeman**

```bash
bin/brakeman
```

Expected: no security warnings. Pay attention to auth-related warnings (session fixation, password reset token handling, mass assignment).

- [ ] **Step 3: Run the full test suite**

```bash
bin/rails test
```

Expected: all tests pass.

- [ ] **Step 4: Manual visual check**

```bash
bin/rails db:drop db:create db:migrate
bin/rails server
```

Open `http://localhost:3000` in a browser and verify:
- With no users: visiting `/` redirects to `/setup`
- Setup wizard shows: Stray logo, username/email/password/confirm fields, carrot "Create account" button
- Create an account, redirected to login
- Login form: logo, email/password fields, carrot "Sign in" button, "Forgot password?" link
- Log in successfully, navbar shows username + "Log out"
- Log out, navbar shows "Log in"
- Visit `/passwords/new` - forgot password form works
- Footer still fixed at bottom, navbar still has charcoal border

If any visual element is wrong, fix the relevant file before committing.

- [ ] **Step 5: Commit any fixes if needed**

```bash
git add -A
git commit -m "fix: address lint/style issues from auth verification"
```

If no fixes were needed, skip this step.

---

## Verification Summary

After all tasks are complete, verify:

| Check | Command | Expected |
|---|---|---|
| Tests pass | `bin/rails test` | All green |
| Lint passes | `bin/rubocop` | No offenses |
| Security scan passes | `bin/brakeman` | No warnings |
| Migration works | `bin/rails db:migrate` | No errors |
| Setup wizard works | Visit `/setup` with no users | Redirects to setup, creates account |
| Login works | POST `/session` | Creates session, redirects to root |
| Logout works | DELETE `/session` | Destroys session, redirects to login |
| Password reset works | POST `/passwords` | Enqueues reset email (if SMTP configured) |
| Navbar shows auth state | Check after login/logout | Username + logout / login link |
| CLI wizard works | `bin/setup-wizard` | Writes .env, prints next steps |
| .env.example exists | `cat .env.example` | All config vars documented |
| .env is gitignored | `git status .env` | Not tracked |