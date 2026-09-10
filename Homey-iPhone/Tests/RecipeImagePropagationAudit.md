# Recipe image propagation audit and client fixes

## Read-only iPad findings

- Bucket: meal-images. Home object key: `<lowercase-home-id>/<lowercase-meal-id>/<lowercase-photo-uuid>.jpg`.
- Home database field: meals.primary_photo_path, a durable object key. Home display signs it for one hour.
- Global database field: global_recipes.image_url, supplied as requested_image_url to save_global_recipe.
- Community to Home: add_global_meal_to_home creates/deduplicates the Home row, then GlobalMealsService downloads the global image, uploads a JPEG into the destination Home folder, and attaches the new key. This is an intentional copy, not a shared object.
- Manual Home creation: creates the meal first, uploads the selected photo, then attaches its object key.
- Website Home creation: selected/imported remote image is downloaded and uploaded using the Home photo pipeline at Save.
- Community contribution: GlobalMealsService uses ONLY draft.importedImageURL. It has no local-photo-to-global conversion or secondary global-photo update. MealEditorViewModel commits the global recipe before the Home photo pipeline. Thus the checked-in iPad implementation does not establish a working manual-photo Community sharing contract.
- Website contribution: retains the website image URL for Community while Home stores its own uploaded copy. These destinations do not share the same uploaded object in the current iPad code.
- Edit: uploads selected replacement, updates Home, preserves unchanged keys. Existing global IDs can be reused; no photo synchronization to a global record is implemented.
- iPad attempts meal_photos metadata creation after upload, nonfatally. It can clean newly uploaded photos after a failed update; this task adds no cleanup/deletion.

## iPhone findings and fixes

The previous Community-to-Home method called only the RPC, whose checked-in implementation initializes primary_photo_path to null. It omitted iPad's image-copy phase. Fixed: await RPC, check destination's existing image, resolve source URL/path, download/re-encode/upload JPEG, and attach the returned key to the specific Home/meal row. Existing edited/copied Home images are preserved.

Concurrent add requests for the same Home/global recipe share one awaited task. If upload succeeds but attachment fails, the path is retained in memory for retry without another upload. Successful attachment survives restart through primary_photo_path. Failed-copy messages acknowledge that the Home recipe already exists; the UI reloads that partial result. The add RPC deduplicates on origin_global_recipe_id. Pending upload memory does not survive an app restart.

RecipeImageReference distinguishes durable Storage paths, existing HTTP(S) URLs, and missing/invalid references. It rejects local-file references and redacts URL query/fragment credentials from image logs. Home and Explore use MealsService.signedImageURL to resolve paths; Explore no longer treats a stored path as a malformed HTTP URL. The existing decoded image cache is reused. No new bucket/cache library/image upload infrastructure was introduced.

Create/Edit save sequencing was already awaited and remains unchanged. Diagnostic logging now covers image source, local presence, remote URL, uploaded key, Home payload, Community payload, and Community-to-Home IDs/references. Home list/detail read the refreshed primary_photo_path. No signed display URL is persisted by the new copy code.

## Verified backend limitations — not fixed client-side

The user supplied bucket metadata confirming meal-images is private. SELECT/INSERT/UPDATE policies require authenticated membership in the Home named by the first folder. DELETE further requires owner/admin. Teaching Explore to resolve a path does not grant another Home's users access to that path.

Manual/replacement-photo Community contribution still has no authorized cross-Home durable image reference under this contract. The global payload uses the imported remote image URL, or nil for manual/removed/replaced imports. No raw private key is published as if it were generally readable, and no expiring signed URL is persisted. A validated shared-image access mechanism is required server-side before manual Home and Community can safely share the same object. No policies, bucket privacy, SQL/schema, or iPad source were changed.

The existing URL-preview function still writes a recipe_imports tracking row. The separate proposed preview-only patch remains unapplied/un-deployed; strict no-write-before-Save is not claimed.

## Test matrix status

| Scenario | Client implementation | Live verification |
| --- | --- | --- |
| Community with image → Home | Added iPad download/upload/attach flow and retry | Pending authenticated test |
| Community without image → Home | RPC succeeds, image remains nil | Pending |
| Manual photo, Community OFF | Existing Home upload/attach retained | Pending |
| Manual photo, Community ON | Home works via existing flow; cross-Home image sharing blocked by backend contract | Not fixed |
| Manual no photo, Community ON | Existing nil-image payload retained | Pending |
| Website photo, Community OFF | Existing download/upload/attach retained | Pending |
| Website photo, Community ON | iPad-compatible external Community URL retained; no shared uploaded Home object | Pending |
| Edit Home photo | Existing upload/update/refresh retained; no global sync | Pending |
| Restart after successful saves | Durable Home keys persisted; display re-signs on load | Pending device restart test |

Passed automated checks: iPhone build and production recipe contract checks, including Storage path format, nil/legacy HTTP image references, rejection of local-file/traversal references, URL log redaction, existing manual/import source mapping, image-removal payloads, and retained Home retry ID/photo path. No live save or cross-Home image visibility success is claimed.

## Files changed

MealsService.swift, RecipeImageReference.swift (new), ExploreRecipeImage.swift, RecipeEditorView.swift (diagnostics), MealsViews.swift (refresh on partial Community copy), recipe contract tests/runner, and this audit document. UI designs and iPad are unchanged.
