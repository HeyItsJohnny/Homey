# Website import flow

## Implemented in iPhone

From Website presents a focused cream URL sheet with paste-friendly input, URL validation, loading guard, green Import Recipe button, and Cancel. Success dismisses that sheet; its onDismiss presents the same shared Create Recipe editor with the imported draft. Cancel from the editor returns to Meals, not to the URL form.

The existing import-recipe-url Edge Function and request/response contract remain in use. No scraping or new importer was added. Supported fields mapped: title, description, cuisine, meal types, source name/domain, original URL, ingredients (numeric quantities or descriptive amounts preserved), ordered directions, prep/cook time, numeric servings, and keywords/tags. Original/normalized URL, import ID, global ID, alreadyExists, total time, and remote image remain in draft.imported. Notes/creator fields are not supplied by this DTO and are not fabricated. Total time remains in import metadata for the existing save pipeline; there is no separate editable Home total-time field.

Imported image is displayed remotely without Storage upload. It can be kept, replaced, or removed. Removal keeps source/import metadata and suppresses the image from Home upload and Community payload. Replacement uses the existing selected-photo upload path at Save and suppresses the stale remote image. The separately diagnosed private-Storage Community image-sharing gap remains unresolved for replacement photos.

Only the existing editor Save calls Home/Community persistence and Storage upload. Community remains optional/default ON; Home saving remains automatic. Partial drafts with empty ingredients/directions reach the shared editor. Existing backend normalized URL/dedup response fields are retained; the checked-in parser currently returns alreadyExists=false/globalRecipeId=null and does not deduplicate saves. No new dedup logic was invented.

## iPad references (read-only)

- Views/ImportRecipeURLView.swift: HTTP(S) URLComponents/host validation and import entry.
- Services/RecipeImportService.swift: import-recipe-url invocation, nested/flat error decoding and SOURCE_BLOCKED handling.
- Models/RecipeImportModels.swift: preview/source DTOs.
- Services/MealEditorViewModel.swift: imported draft mapping and image handling.

## Error handling and diagnostics

Malformed/empty URLs disable Import. Nested/flat backend error codes map to friendly messages, including SOURCE_BLOCKED, auth/access errors, missing recipes, and invalid/parse failures. Network/unexpected responses use a generic retry message. Failures keep the URL sheet open. DEBUG logs show a URL with credentials/query/fragment stripped, importer stage, recipe title, image presence and ingredient/step counts, failure code/type/message. No clipboard reads occur automatically.

## No-write-before-Save limitation

The checked-in Edge Function inserts recipe_imports before fetching the website, updates it on success, and marks it failed on error. iPad calls this same endpoint, so iPad preview is not strictly write-free either. Cancel avoids Home/global recipe, ingredient, favorite, planner, and image writes, but cannot undo/prevent that tracking row from the current client-only contract.

RecipeImportPreviewOnly.proposed.patch is an UNAPPLIED opt-in patch for the existing Edge Function and the iPhone request flag. It preserves default iPad behavior, authentication, Home membership checks, normalization, and parsing; preview-only requests skip all tracking inserts/updates and use a transient response import ID. No schema or new function is proposed. Deploy the Edge Function change before applying/shipping the iPhone opt-in. This patch has not been deployed or integration-tested and is outside the completed iPhone-only change.

## Verification

Passed: iPhone simulator-target build; production contract/mapping tests for URL trimming/invalid schemes/missing host, safe log URL, SOURCE_BLOCKED decoding, imported title/source/normalized URL, retained remote image and image removal, and existing save/retry contracts.

Pending interactive/authenticated checks: sheet presentation and paste, successful website import and separate editor presentation, field prefill/edit, remote photo keep/replace/remove, Cancel, Save, Community ON/OFF, blocked page, network failure, small/Max layout. Simulator Computer Use was not approved earlier in this session. No live import was invoked during this task.
