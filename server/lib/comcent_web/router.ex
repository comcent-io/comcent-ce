defmodule ComcentWeb.Router do
  use ComcentWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
    plug(ComcentWeb.Plugs.SnakeCaseParams)
  end

  # Health check route - no authentication required
  scope "/", ComcentWeb do
    get("/health", HealthController, :health)
  end

  # Pipeline for API v2 with JWT authentication
  pipeline :api_v2_auth do
    plug(:accepts, ["json"])
    plug(ComcentWeb.Plugs.ApiV2Auth)
  end

  pipeline :api_any_auth do
    plug(:accepts, ["json"])
    plug(ComcentWeb.Plugs.ApiAnyAuth)
  end

  pipeline :org_api_key_auth do
    plug(:accepts, ["json"])
    plug(ComcentWeb.Plugs.OrgApiKeyAuth)
  end

  pipeline :ensure_org_admin_member do
    plug(:accepts, ["json"])
    plug(ComcentWeb.Plugs.ApiV2Auth)
    plug(ComcentWeb.Plugs.EnsureOrgAdminMember, role: :ADMIN)
  end

  pipeline :admin_json do
    plug(:accepts, ["json"])
    plug(ComcentWeb.Plugs.AdminAuth)
  end

  pipeline :admin_html do
    plug(:accepts, ["html"])
    plug(ComcentWeb.Plugs.AdminAuth)
  end

  pipeline :ensure_is_org_member do
    plug(:accepts, ["json"])
    plug(ComcentWeb.Plugs.ApiV2Auth)
    plug(ComcentWeb.Plugs.EnsureIsOrgMember)
  end

  scope "/admin", ComcentWeb do
    pipe_through([:admin_html])
    # Admin HTML routes
  end

  scope "/admin/api", ComcentWeb do
    pipe_through([:api, :admin_json])
    # Admin API routes
  end

  scope "/api/v2/:subdomain", ComcentWeb do
    pipe_through([:api, :api_v2_auth, :ensure_org_admin_member])
    # V2 Admin API routes will be added here
    post("/queues", QueueController, :create)
    put("/queues/:id", QueueController, :update)
    get("/queues", QueueController, :get_queues)
    delete("/queues/:id", QueueController, :delete)
    get("/queues/:id", QueueController, :get_queue)
    get("/queues/:id/state", QueueController, :get_queue_state)
    post("/queues/:id/members", QueueController, :add_member)
    delete("/queues/:id/members/:member_id", QueueController, :remove_member)
    get("/call-story/:call_story_id", CallStoryController, :get_call_story)
    get("/call-story/:call_story_id/transcript", CallStoryController, :get_transcript)
    get("/call-story/:call_story_id/summary", CallStoryController, :get_summary)
    get("/call-story/:call_story_id/sentiment", CallStoryController, :get_sentiment)
    get("/call-stories", CallStoryController, :get_call_stories)
    get("/settings/ai-analysis", OrgAiSettingsController, :get)
    post("/settings/ai-analysis", OrgAiSettingsController, :update)
    get("/numbers", NumberController, :get_numbers)
    post("/numbers", NumberController, :create)
    put("/numbers/:id", NumberController, :update)
    delete("/numbers/:id", NumberController, :delete)
    post("/numbers/:id/set-default", NumberController, :set_default)
    get("/sip-trunks", SipTrunkController, :get_sip_trunks)
    post("/sip-trunks", SipTrunkController, :create)
    put("/sip-trunks/:id", SipTrunkController, :update)
    delete("/sip-trunks/:id", SipTrunkController, :delete)

    # Voice Bots
    get("/voice-bots", VoiceBotController, :get_voice_bots)
    post("/voice-bots", VoiceBotController, :create)
    get("/voice-bots/:id", VoiceBotController, :get_voice_bot)
    put("/voice-bots/:id", VoiceBotController, :update)
    delete("/voice-bots/:id", VoiceBotController, :delete)

    # Org API Keys
    get("/settings/api-keys", OrgApiKeyController, :get_api_keys)
    post("/settings/api-keys", OrgApiKeyController, :create)
    delete("/settings/api-keys/:api_key", OrgApiKeyController, :delete)

    # Webhooks
    get("/settings/webhooks", OrgWebhookController, :get_webhooks)
    post("/settings/webhooks", OrgWebhookController, :create)
    put("/settings/webhooks/:id", OrgWebhookController, :update)
    delete("/settings/webhooks/:id", OrgWebhookController, :delete)

    # Members (admin operations)
    get("/admin/members", AdminMemberController, :list_members)
    get("/admin/members/:member_id", AdminMemberController, :get_member)
    put("/admin/members/:member_id/role", AdminMemberController, :update_role)

    post(
      "/admin/members/:member_id/regenerate-password",
      AdminMemberController,
      :regenerate_password
    )

    post("/members/invite", AdminMemberController, :invite_member)
    post("/members/invite/:invite_id/resend", AdminMemberController, :resend_invite)

    # Billing
    get("/playback/:file_name", FileController, :get_playback)
    get("/call-story/:call_story_id/record/:file_name", FileController, :get_recording)
    get("/compliance/downloads/:file_name", FileController, :get_compliance_download)
    get("/uploads/get-signed-url", FileController, :get_upload_signed_url)
    delete("/uploads", FileController, :delete_upload)




  end

  scope "/api/v2/:subdomain", ComcentWeb do
    pipe_through([:api, :api_v2_auth, :ensure_is_org_member])
    # V2 API routes will be added here
    get("/test", HealthController, :health)
    get("/me/access", MemberController, :get_access)
    post("/members/presence", MemberController, :update_presence)
    get("/members/presence", MemberController, :get_presence)
    get("/members", MemberController, :get_all_members)
    post("/members/default-number", MemberController, :update_default_number)
    get("/me/context", MemberController, :get_app_context)
    post("/me/api-keys", MemberController, :create_api_key)
    delete("/me/api-keys/:api_key", MemberController, :delete_api_key)
    get("/dashboard/aggregate-presence", MemberController, :get_aggregate_presence)
    get("/calls/live", DashboardController, :get_live_calls)


  end

  scope "/api/v2/:subdomain/widget", ComcentWeb do
    pipe_through([:api])

    options("/init-config", MemberController, :options_widget)
  end

  scope "/api/v2/:subdomain/widget", ComcentWeb do
    pipe_through([:api, :api_any_auth, :ensure_is_org_member])

    get("/init-config", MemberController, :get_widget_init_config)
  end

  scope "/api/v2", ComcentWeb do
    pipe_through([:api])

    get("/auth/config", AuthController, :config)
    post("/auth/login", AuthController, :login)
    post("/auth/register", AuthController, :register)
    post("/auth/verify-email", AuthController, :verify_email)
    post("/auth/resend-verification", AuthController, :resend_verification)
    get("/auth/oauth/:provider/start", AuthController, :oauth_start)
    get("/auth/oauth/:provider/callback", AuthController, :oauth_callback)
  end

  scope "/api/v2", ComcentWeb do
    pipe_through([:api, :api_v2_auth])

    get("/user/session", UserController, :get_session)
    get("/user/orgs", UserController, :get_orgs)
    get("/user/org-creation-context", UserController, :get_org_creation_context)
    post("/user/orgs", UserController, :create_org)
    get("/user/invitations/:id", UserController, :get_invitation)
    post("/user/invitations/:id/accept", UserController, :accept_invitation)
    post("/user/accept-terms", UserController, :accept_terms)
  end

  scope "/api/v2/public/:subdomain", ComcentWeb do
    pipe_through([:api])

    options("/user-token", UserController, :options_public_api)
  end

  scope "/api/v2/public/:subdomain", ComcentWeb do
    pipe_through([:api, :org_api_key_auth])

    get("/user-token", UserController, :generate_user_token)
  end

  scope "/api/v2", ComcentWeb do
    pipe_through([:api])

  end

  pipeline :internal do
    plug(:accepts, ["json"])
    plug(ComcentWeb.Plugs.BasicAuth)
  end

  scope "/internal-api", ComcentWeb do
    pipe_through(:internal)

    # Playback route there is an exception rule for Basic Auth for these two routes
    # Some day we need to fix it.
    head("/playback/:subdomain/:key", Internal.PlaybackController, :head_playback)
    get("/playback/:subdomain/:key", Internal.PlaybackController, :get_playback)

    post("/user/credentials", Internal.UserCredentialsController, :create)
    post("/number/sip-trunk", Internal.SipTrunkController, :create)
    get("/voice-bot/:id", Internal.VoiceBotController, :get_voice_bot)
    post("/user/presence", Internal.MemberController, :update_presence)

    scope "/xml-curl" do
      post("/directory", Internal.DirectoryController, :create)
      post("/configuration", Internal.ConfigurationController, :create)
      post("/httapi", Internal.HttpapiController, :create)
      post("/dialplan", Internal.DialplanController, :create)
    end
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:comcent, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through([:fetch_session, :protect_from_forgery])

      live_dashboard("/dashboard", metrics: ComcentWeb.Telemetry)
      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end
  end
end
