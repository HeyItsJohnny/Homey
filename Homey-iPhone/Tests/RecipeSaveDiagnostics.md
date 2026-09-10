# Recipe save diagnosis

## Confirmed client defects

- Home and Community RPC payloads omitted nullable arguments via `encodeIfPresent`. The iPad sends every RPC argument, using JSON null for absent values. The checked-in `save_global_recipe` signature requires all 15 named arguments; omission prevents function matching. No live PostgREST error code has been captured yet.
- Home ingredient quantities were encoded as strings. The iPad uses numeric Decimal quantities. The iPhone now converts numeric/fraction input and preserves nonnumeric imported amounts in ingredient names, as the iPad does.
- Community payloads discarded imported image URLs and always used source type `user`. They preserve the URL and use `community` for manual contributions or `url` for imports. The iPad still sends `manual`, but the user-provided deployed constraint rejects that value.
- Retrying after Home succeeded could insert another Home recipe. The editor now retains the returned Home ID and photo path for retries during that editor session.
- Refresh previously included unrelated planner/favorite requests and swallowed load errors. Save now performs a throwing Home recipe refresh and signals Explore separately. A refresh failure is reported as a saved recipe with a refresh problem, not an unsaved recipe.

## Flow

Validation → authentication → Home RPC → imported photo download/upload and attachment if applicable → optional Community RPC → recipe refresh → dismissal.

Automatic Home saving remains enabled. Only Share with Community is optional. Community-only and no-destination combinations are not exposed, per the user's clarification.

DEBUG logs use `[RecipeSave]` and include the stage, returned IDs, error type, and PostgREST code/message/details/hint. No credentials or auth headers are logged. Release builds do not emit this diagnostic output. User-facing errors are friendly and keep the editor open.

## Partial saves and backend limits

There is no cross-destination transaction or rollback in the current client flow. Home remains saved if a later image/Community operation fails. Retry uses the known Home ID; no destructive cleanup is attempted. A network failure after a server commit but before receipt of the ID remains ambiguous, and closing the editor loses in-memory retry IDs. The existing RPC offers no client-supplied idempotency key.

URL preview creates no Home or Community recipe. The existing Edge Function does create/update a `recipe_imports` tracking row before Save. Enforcing literally zero database writes during preview would require a backend change, which was not authorized.

The shared iPhone editor now supports PhotosPicker for manual and replacement photos; Scan remains a Coming Soon placeholder. Selected photos are downsampled and encoded as JPEG, and use the same uploadPhoto service as imported photos. Images use the existing meal-images bucket and <home-id>/<meal-id>/<photo-uuid>.jpg path. Unchanged edit photos retain their stored path without uploading again. Storage/RLS was not changed.

## Verification

- Homey-iPhone simulator build: passed; app installed and launched.
- `python3 Homey-iPhone/Tests/run-recipe-save-checks.py`: passed. Tests compile the production payloads and compare against read-only iPad types, including nullable arguments, numeric/fraction quantities, imported image/source metadata, and retry ID/photo path.
- iPad and Supabase files: unchanged.
- Live Home-only/Both and manual/imported image/no-image saves: pending authenticated testing. Simulator is signed out; no live save or underlying server error is claimed.
- UIKit keyboard haptic warnings: untouched.

To diagnose a remaining failure, reproduce once in the DEBUG build and collect the `[RecipeSave] FAILED stage=...` block with the following error details.
