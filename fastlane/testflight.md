# Using Github Actions + FastLane to deploy to TestFlight: the "Browser Build" method

These instructions allow you to build Trio without having access to a Mac.

* You can install Trio on phones via TestFlight that are not connected to your computer
* You can send builds and updates to those you care for
* You can install Trio on your phone using only the TestFlight app if a phone was lost or the app is accidentally deleted
* You do not need to worry about specific Xcode/Mac versions for a given iOS

## **Automatic Builds**
> 
> The browser build defaults to automatically updating and building a new version of Trio according to this schedule:
> - automatically checks for updates weekly on Wednesdays and if updates are found, it will build a new version of the app
> - automatically builds once a month regardless of whether there are updates on the first of the month
> - with each scheduled run (weekly or monthly), a successful Build Trio log appears - if the time is very short, it did not need to build - only the long actions (>10 minutes) built a new Trio app
> 
> It also creates an alive branch, if you don't already have one. See [Why do I have an alive branch?](#why-do-i-have-an-alive-branch).
>

## Introduction

The setup steps are somewhat involved, but nearly all are one time steps. Subsequent builds are trivial. Your app must be updated once every 90 days, but it's a simple click to make a new build and can be done from anywhere.

Note that TestFlight requires apple id accounts 13 years or older. This can be circumvented by logging into Media & Purchase on the child's phone with an adult's account. More details on this can be found in [LoopDocs](https://loopkit.github.io/loopdocs/gh-actions/gh-deploy/#install-testflight-loop-for-child).

This method for building without a Mac was ported from Loop. If you have used this method for Loop or one of the other DIY apps (Loop Caregiver, Loop Follow, Xdrip4iOS), some of the steps can be re-used and the full set of instructions does not need to be repeated. This will be mentioned in relevant sections below.

There are more detailed instructions in LoopDocs for doing Browser Builds of Loop and other apps, including troubleshooting and build errors. Please refer to [LoopDocs](https://loopkit.github.io/loopdocs/gh-actions/gh-other-apps/) for more details.

## Prerequisites

* A [github account](https://github.com/signup). The free level comes with plenty of storage and free compute time to build Trio, multiple times a day, if you wanted to.
* A paid [Apple Developer account](https://developer.apple.com).
* Some time. Set aside a couple of hours to perform the setup. 
* Use the same GitHub account for all "Browser Builds" of the various DIY apps.

## Save 6 Secrets

You require 6 Secrets (alphanumeric items) to use the GitHub build method and if you use the GitHub method to build other apps, e.g., Loop Follow or Xdrip4iOS, you will use the same 6 Secrets for each app you build with this method. Each secret is indentified below by `ALL_CAPITAL_LETTER_NAMES`.

* Four Secrets are from your Apple Account
* Two Secrets are from your GitHub account
* Be sure to save the 6 Secrets in a text file using a text editor
    - Do **NOT** use a smart editor, which might auto-correct and change case, because these Secrets are case sensitive

## Generate App Store Connect API Key

This step is common for all GitHub Browser Builds; do this step only once. You will be saving 4 Secrets from your Apple Account in this step.

1. Sign in to the [Apple developer portal page](https://developer.apple.com/account/resources/certificates/list).
1. Copy the Team ID from the upper right of the screen. Record this as your `TEAMID`.
1. Go to the [App Store Connect](https://appstoreconnect.apple.com/access/integrations/api) interface, click the "Integrations" tab, and create a new key with "Admin" access. Give it the name: "FastLane API Key".
1. Record the issuer id; this will be used for `FASTLANE_ISSUER_ID`.
1. Record the key id; this will be used for `FASTLANE_KEY_ID`.
1. Download the API key itself, and open it in a text editor. The contents of this file will be used for `FASTLANE_KEY`. Copy the full text, including the "-----BEGIN PRIVATE KEY-----" and "-----END PRIVATE KEY-----" lines.

## Create GitHub Personal Access Token

If you have previously built another app using the "browser build" method, you can can re-use your previous personal access token (`GH_PAT`) and skip this step.

Log into your GitHub account to create a personal access token; this is one of two GitHub secrets needed for your build.

1. Create a [new personal access token](https://github.com/settings/tokens/new):
    * Enter a name for your token, use "FastLane Access Token".
    * Change the Expiration selection to `No expiration`.
    * Select the `workflow` permission scope - this also selects `repo` scope.
    * Click "Generate token".
    * Copy the token and record it. It will be used below as `GH_PAT`.

## Make up a Password

This is the second one of two GitHub secrets needed for your build.

The first time you build with the GitHub Browser Build method for any DIY app, you will make up a password and record it as `MATCH_PASSWORD`. Note, if you later lose `MATCH_PASSWORD`, you will need to delete and make a new Match-Secrets repository (next step).

## Setup GitHub Match-Secrets Repository

The creation of the Match-Secrets repository is a common step for all GitHub Browser Builds; do this step only once. You must be logged into your GitHub account.

1. Create a [new empty repository](https://github.com/new) titled `Match-Secrets`. It should be private.

Once created, you will not take any direct actions with this repository; it needs to be there for the GitHub to use as you progress through the steps.

## Setup Github Trio repository
1. Fork https://github.com/nightscout/Trio into your account. If you already have a fork of Trio in GitHub, you can't make another one. You can continue to work with your existing fork, or delete that from GitHub and then and fork https://github.com/nightscout/Trio.
1. In the forked Trio repo, go to Settings -> Secrets and variables -> Actions.
1. For each of the following secrets, tap on "New repository secret", then add the name of the secret, along with the value you recorded for it:
    * `TEAMID`
    * `FASTLANE_ISSUER_ID`
    * `FASTLANE_KEY_ID`
    * `FASTLANE_KEY`
    * `GH_PAT`
    * `MATCH_PASSWORD`

## Validate repository secrets

This step validates most of your six Secrets and provides error messages if it detects an issue with one or more.

1. Click on the "Actions" tab of your Trio repository and enable workflows if needed
1. On the left side, select "1. Validate Secrets".
1. On the right side, click "Run Workflow", and tap the green `Run workflow` button.
1. Wait, and within a minute or two you should see a green checkmark indicating the workflow succeeded.
1. The workflow will check if the required secrets are added and that they are correctly formatted. If errors are detected, please check the run log for details.

## Add Identifiers for Trio App

1. Click on the "Actions" tab of your Trio repository.
1. On the left side, select "2. Add Identifiers".
1. On the right side, click "Run Workflow", and tap the green `Run workflow` button.
1. Wait, and within a minute or two you should see a green checkmark indicating the workflow succeeded.

## Create App Group

If you have already built Trio via Xcode using this Apple ID, you can skip on to [Create Trio App in App Store Connect](#create-trio-app-in-app-store-connect).
_Please note that in default builds of Trio, the app group is actually identical to the one used with Loop, so please enter these details exactly as described below. This is to ease the setup of apps such as Xdrip4iOS. It may require some caution if transfering between Trio and Loop._

1. Go to [Register an App Group](https://developer.apple.com/account/resources/identifiers/applicationGroup/add/) on the apple developer site.
1. For Description, use "Loop App Group".
1. For Identifier, enter "group.com.TEAMID.loopkit.LoopGroup", substituting your team id for `TEAMID`.
1. Click "Continue" and then "Register".

## Add App Group to Bundle Identifiers

1. Go to [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list) on the Apple developer site.
1. For each of the following identifier names:
    * FreeAPS
    * FreeAPS watchkitapp
    * FreeAPS watchkitapp watchkitextension
1. Click on the identifier's name.
1. On the "App Groups" capabilies, click on the "Configure" button.
1. Select the "Loop App Group" _(yes, "Loop App Group" is correct)_
1. Click "Continue".
1. Click "Save".
1. Click "Confirm".
1. Remember to do this for each of the identifiers above.

## Create Trio App in App Store Connect

If you have created a Trio app in App Store Connect before, you can skip this section as well.

1. Go to the [apps list](https://appstoreconnect.apple.com/apps) on App Store Connect and click the blue "plus" icon to create a New App.
    * Select "iOS".
    * Select a name: this will have to be unique, so you may have to try a few different names here, but it will not be the name you see on your phone, so it's not that important.
    * Select your primary language.
    * Choose the bundle ID that matches the `BUNDLE_IDENTIFIER` in your `Config.xcconfig` file
       * this is typically `org.nightscout.TEAMID.trio` with `TEAMID` matching your team id
    * SKU can be anything; e.g. "123".
    * Select "Full Access".
1. Click Create

You do not need to fill out the next form. That is for submitting to the app store.

## Create Building Certficates

1. Go back to the "Actions" tab of your Trio repository in github.
1. Select "3. Create Certificates".
1. Click "Run Workflow", and tap the green button.
1. Wait, and within a minute or two you should see a green checkmark indicating the workflow succeeded.

## Build Trio!

1. Click on the "Actions" tab of your Trio repository.
1. On the left side, select "4. Build Trio".
1. Click "Run Workflow", select your branch, and tap the green button.
1. You have some time now. Go enjoy a coffee. The build should take about 15 minutes.
1. Your app should eventually appear on [App Store Connect](https://appstoreconnect.apple.com/apps).
1. For each phone/person you would like to support Trio on:
    * Add them in [Users and Access](https://appstoreconnect.apple.com/access/users) on App Store Connect.
    * Add them to your TestFlight Internal Testing group.

## TestFlight and Deployment Details

For more details, please refer to [LoopDocs: Set Up Users](https://loopkit.github.io/loopdocs/gh-actions/gh-first-time/#set-up-users-and-access-testflight) and [LoopDocs: Deploy](https://loopkit.github.io/loopdocs/gh-actions/gh-deploy/)

## Automatic Build FAQs

### Why do I have an `alive` branch?

If a GitHub repository has no activity (no commits are made) in 60 days, then GitHub disables the ability to use automated actions for that repository. We need to take action more frequently than that or the automated build process won't work.

The `build_trio.yml` file uses a special branch called `alive` and adds a dummy commit to the `alive` branch at regular intervals. This "trick" keeps the Actions enabled so the automated build works.

The branch `alive` is created automatically for you. Do not delete or rename it! Do not modify `alive` yourself; it is not used for building the app.
