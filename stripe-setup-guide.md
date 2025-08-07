# 🚀 Stripe Setup Guide for HealthGuide

Think of Stripe like a cash register for your app - it helps you collect money from customers safely. Let's set it up step by step!

## 📝 What You'll Need First
- A computer with internet
- A bank account (for receiving money)
- Your business information
- About 30 minutes

---

## Step 1: Create Your Stripe Account 🏪

1. **Go to Stripe's website**
   - Open your web browser
   - Type: `stripe.com`
   - Click the "Sign up" button (usually in the top right)

2. **Fill in your information**
   - Your email address
   - Your name
   - Create a password (make it strong!)
   - Your country (United States)

3. **Verify your email**
   - Check your email inbox
   - Click the link Stripe sent you
   - This proves you own the email

---

## Step 2: Set Up Your Business 🏢

After logging in, Stripe will ask about your business:

1. **Business Type**
   - Choose "Individual" if it's just you
   - Choose "Company" if you have a registered business

2. **Business Details**
   - Business name: "HealthGuide" (or your app name)
   - What you sell: "Software/Digital Services"
   - Website: Your website (or put "Coming soon" if you don't have one)

3. **Bank Account** (where you want money sent)
   - Your bank name
   - Routing number (9 digits at bottom of check)
   - Account number
   - Don't worry - Stripe is super safe!

---

## Step 3: Get Your Secret Keys 🔑

Think of these like special passwords that let your app talk to Stripe:

1. **Find your keys**
   - In Stripe, click "Developers" in the left menu
   - Click "API keys"
   - You'll see two types of keys:

2. **Test Keys** (for practice - use these first!)
   - **Publishable key**: Starts with `pk_test_`
   - **Secret key**: Starts with `sk_test_`
   - Click "Reveal test key" to see the secret one

3. **Live Keys** (for real money - use when ready)
   - **Publishable key**: Starts with `pk_live_`
   - **Secret key**: Starts with `sk_live_`

⚠️ **SUPER IMPORTANT**: 
- The **publishable key** is like your store's address - okay to share
- The **secret key** is like your safe combination - NEVER share it!

---

## Step 4: Create Your Subscription Product 📦

This tells Stripe what you're selling:

1. **Go to Products**
   - Click "Products" in the left menu
   - Click "Add product" button

2. **Fill in product details**
   - **Name**: HealthGuide Premium
   - **Description**: Monthly subscription with all premium features
   - **Image**: Upload your app icon (optional but nice!)

3. **Set the price**
   - Click "Add pricing"
   - **Price**: 8.99
   - **Currency**: USD
   - **Billing period**: Monthly
   - Click "Save product"

4. **Copy the Price ID**
   - After saving, you'll see something like: `price_1AbCdEfGhIjKlMnOp`
   - Copy this - you'll need it!

---

## Step 5: Set Up the Free Trial 🎁

1. **Edit your product**
   - Click on "HealthGuide Premium"
   - Click on the price you created

2. **Add trial period**
   - Look for "Trial period"
   - Enter: 7 days
   - Save changes

---

## Step 6: Add Keys to Your App 📱

### In Xcode (your iOS app):

1. **Open Info.plist**
   - Find the file called `Info.plist` in your project
   - Right-click and choose "Open As > Source Code"

2. **Add these lines** (put them before the last `</dict>`):
```xml
<key>STRIPE_PUBLISHABLE_KEY</key>
<string>pk_test_YOUR_KEY_HERE</string>

<key>API_KEY</key>
<string>your-secret-api-key-for-backend</string>
```
   - Replace `pk_test_YOUR_KEY_HERE` with your actual test publishable key
   - The API_KEY is something you make up (like a password between your app and server)

### In your Backend folder:

1. **Open the .env file**
   - Find the file called `.env` in healthguide-backend folder

2. **Update these lines**:
```
STRIPE_SECRET_KEY=sk_test_YOUR_SECRET_KEY_HERE
STRIPE_MONTHLY_PRICE_ID=price_YOUR_PRICE_ID_HERE
```
   - Replace with your actual keys from Stripe

---

## Step 7: Test Everything 🧪

### Test in Stripe:

1. **Use test credit cards**
   - Card number: `4242 4242 4242 4242`
   - Expiry: Any future date (like 12/34)
   - CVC: Any 3 digits (like 123)
   - ZIP: Any 5 digits (like 12345)

2. **Check the dashboard**
   - After a test payment, go to Stripe Dashboard
   - Click "Payments" - you should see your test payment!

### Test in your app:

1. **Run the backend**
```bash
cd healthguide-backend
npm run dev
```

2. **Run your iOS app**
   - Open Xcode
   - Press the play button
   - Try subscribing!

---

## Step 8: Set Up Webhooks 🔔

Webhooks are like text messages that Stripe sends your app when something happens:

1. **In Stripe Dashboard**
   - Click "Developers" → "Webhooks"
   - Click "Add endpoint"

2. **For testing (local)**:
   - Endpoint URL: `http://localhost:3000/api/subscriptions/webhook`
   - Events to send: Select "payment_intent.succeeded" and "customer.subscription.deleted"

3. **Copy the webhook secret**
   - After creating, click on the webhook
   - Copy the "Signing secret" (starts with `whsec_`)
   - Add to your .env file: `STRIPE_WEBHOOK_SECRET=whsec_YOUR_SECRET`

---

## Step 9: Going Live (When Ready!) 🎉

When you're ready for real customers:

1. **Activate your account**
   - Complete any remaining Stripe verification
   - Add tax information if needed

2. **Switch to live keys**
   - Replace all `pk_test_` with `pk_live_` keys
   - Replace all `sk_test_` with `sk_live_` keys
   - Update webhook URLs to your real server

3. **Test with a real card**
   - Make a real $8.99 payment
   - Then cancel and check refund works
   - Make sure you get the money in your bank!

---

## 🚨 Important Safety Rules

### NEVER DO:
- ❌ Put secret keys (sk_) in your iOS app
- ❌ Share secret keys with anyone
- ❌ Commit secret keys to GitHub
- ❌ Send secret keys in email

### ALWAYS DO:
- ✅ Keep secret keys only on your server
- ✅ Use test keys first
- ✅ Test everything before going live
- ✅ Keep backups of your keys (in a password manager)

---

## 📞 If You Get Stuck

1. **Stripe Support**: support.stripe.com
2. **Stripe Docs**: stripe.com/docs
3. **Test Dashboard**: dashboard.stripe.com/test

---

## Quick Checklist ✅

Before going live, make sure:

- [ ] Stripe account verified
- [ ] Bank account connected
- [ ] Product created ($8.99/month)
- [ ] 7-day trial configured
- [ ] Test keys working
- [ ] Backend server running
- [ ] Webhooks set up
- [ ] Tested full payment flow
- [ ] Tested cancellation & refund
- [ ] Ready to switch to live keys

---

## Your Keys Cheat Sheet 📋

Keep track of these (fill them in):

**Test Mode:**
- Publishable Key: `pk_test_________________________`
- Secret Key: `sk_test_________________________`
- Price ID: `price_________________________`
- Webhook Secret: `whsec_________________________`

**Live Mode (when ready):**
- Publishable Key: `pk_live_________________________`
- Secret Key: `sk_live_________________________`
- Price ID: `price_________________________`
- Webhook Secret: `whsec_________________________`

---

Remember: It's like learning to ride a bike - seems hard at first, but once you get it, you've got it! Take it step by step, and you'll have payments working in no time! 🎈