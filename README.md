# extension-social-auth

Defold native extension repo for the social authentication bridge used by Mindset.

## Current scope

This repo contains the extracted native bridge that powers the social auth flow used by profiles, friends, duels, and push-linked social identity in the game.

For compatibility with the existing game code, the exported Lua module name is still `firebaseauth` in this first extraction pass.

The repo also carries the Lua adapter at `assets/scripts/firebase_auth_native.lua`, so consumers can keep the same `require("assets.scripts.firebase_auth_native")` call after switching to the dependency.

## Repo layout

- `extension-social-auth/`: the native extension source and manifests
- `assets/scripts/firebase_auth_native.lua`: Lua-facing adapter used by the game
- `socialauth/async_dispatch.lua`: private callback queue helper used by the adapter
- `main/`: tiny sample Defold app entry point
- `input/`: sample input bindings
- `game.project`: sample Defold project file

## Notes

- The extracted extension contents are based on the in-repo `extension-firebase-auth` implementation.
- Native symbol names and the Lua API were intentionally kept stable for the first extraction so the game can adopt the repo without a simultaneous API rename.
- If you want, the next pass can rename the Lua surface from `firebaseauth` to `socialauth` once the consuming game code is updated.
- The callback queue is intentionally bundled here so the adapter does not depend on a project-local helper module.

## Using it from Mindset

1. Move this repo outside the `mindset` project tree.
2. Push it to GitHub.
3. Add it to `mindset/game.project` as a Defold dependency, for example:

`dependencies#N = https://github.com/Magicave/extension-social-auth/archive/refs/heads/master.zip`

The Mindset code can continue to require `assets.scripts.firebase_auth_native` after the dependency is added.
