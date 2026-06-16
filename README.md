# extension-social-auth

Defold native extension repo for the social authentication bridge used by Mindset.

## Current scope

This repo contains the extracted native bridge that powers the social auth flow used by profiles, friends, duels, and push-linked social identity in the game.

For compatibility with the existing native code, the exported Defold extension Lua global is still `firebaseauth` in this first extraction pass.

The repo carries the Lua adapter at `socialauth/firebase_auth_native.lua`, exposed to consumers as `require("socialauth.firebase_auth_native")`.

## Repo layout

- `extension-social-auth/`: the native extension source and manifests
- `socialauth/firebase_auth_native.lua`: Lua-facing adapter used by the game
- `socialauth/async_dispatch.lua`: private callback queue helper used by the adapter
- `main/`: tiny sample Defold app entry point
- `input/`: sample input bindings
- `game.project`: sample Defold project file
