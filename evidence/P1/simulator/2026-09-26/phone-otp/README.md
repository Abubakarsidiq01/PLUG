# Phone OTP simulator evidence

September 26, 2026: full signup → duplicate signup → sign-in scenario passed on
iPhone 17 Pro Simulator. A verified phone creates an account; trying signup again
shows the account-exists message, whose Sign in action returns to the existing account.

Delivery was local-only development delivery on port 8082 and the isolated
plug_auth_regression database. No real SMS was sent and no delivery claim is made.
Test codes were read from an owner-only temporary file outside protected Desktop
folders. The screenshots contain account state, not codes or credentials.
