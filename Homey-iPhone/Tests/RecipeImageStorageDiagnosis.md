# Recipe image Storage failure

## Confirmed client mismatch

The iPad source of truth is `Homey-iPad/Homey/Features/Meals/Services/MealService.swift`, in `uploadMealPhoto` and `mealPhotoPath`.

| Contract | iPad | iPhone before fix | iPhone after fix |
| --- | --- | --- | --- |
| Bucket | `meal-images` | Same | Same |
| Object key | `<home-id>/<meal-id>/<photo-uuid>.jpg` | `homes/<home-id>/meals/<meal-id>/<photo-uuid>.jpg` | Matches iPad |
| UUID casing | Lowercase | Lowercase | Lowercase |
| Filename | New UUID, normalized `.jpg` | New UUID, `.jpg` | Same |
| User folder | None | None | None |
| Upload | Storage `.upload`, `upsert: true` | Same | Same |
| Content type/cache | `image/jpeg`, `3600` | Same | Same |
| Authentication | Reads `client.auth.session.user.id` immediately before upload | Save flow checks session before saving the Home row | Also reads current session/user immediately before upload |
| Display URL | Signed URL, 3600 seconds | Signed URL, 3600 seconds; also accepts existing remote URLs | Unchanged |
| Main recipe field | Raw object key in `primary_photo_path`, via `requested_primary_photo_path` | Same | Same, with corrected object key |

The path meal ID is the persisted `meals.id`, not the separate `meal_recipes.id`. Neither client uses the user ID in the object key. The signed-in user authenticates the request; the Home UUID identifies the active Home. Actual membership/policy evaluation happens on the server.

The iPad additionally attempts a `meal_photos` metadata insert after Storage succeeds, with `uploaded_by` set to the authenticated user ID. Metadata-insert failure is nonfatal there. iPhone does not insert this metadata row. This difference cannot explain the reported Storage upload failure because the iPad inserts metadata only after upload succeeds. No metadata behavior was added to iPhone.

## Policy evidence and SQL

No `storage.objects`, `storage.foldername`, or `meal-images` policy definitions were found in the workspace's `supabase/` files (or other checked-in SQL). This does not mean the deployed policies are absent. No live policy catalog or authenticated failing request was available for inspection.

The path mismatch is verified; the exact deployed INSERT predicate and why it rejects the request remain unverified. A policy expecting the Home UUID in the first folder would receive `homes` from the old client, but that is a conditional explanation, not a claim about the deployed SQL.

Fix the client to match iPad first. No SQL patch is warranted from the available evidence and no SQL/schema changes were made. If a retry still fails, use the new DEBUG diagnostics and inspect the deployed Storage policies/Home membership before proposing any policy change.

## DEBUG diagnostics

Immediately before upload, iPhone logs `[RecipeImage] bucket=`, `path=`, `userID=`, `homeID=`, and `recipeID=`. The last value is the persisted meal ID used in the key. No keys or authentication tokens are logged. Empty image data is rejected before upload, matching iPad's preflight behavior.

## Partial save behavior retained

- iPad Create: saves the meal first and remembers its ID, uploads the image, then saves its object key back to the same meal.
- iPad manual-photo failure: keeps the meal and reports a partial-save error. Subsequent save uses the persisted ID/update path.
- iPad imported-photo failure during Create: can discard the imported photo selection and finish saving without an image.
- iPad update/retry: uploads a selected image before updating the persisted meal; if the later save fails after upload succeeds, it attempts to delete that newly uploaded photo and its metadata. Initial Create does not perform this same cleanup.
- iPhone: continues to save the meal first, upload, then attach the key. Image failure keeps the editor open and retains the saved meal ID for retry. No rollback, upload-order, or partial-save redesign was made.

## Verification

- Production contract test checks exact three-component lowercase key and UUID `.jpg` filename.
- Existing recipe payload/edit/retry tests remain in the same suite.
- Build the Homey-iPhone simulator target.
- Live retest pending: save a selected photo; confirm new DEBUG path; confirm upload and attachment succeed; open the signed image.
- Retry a previously failed save without closing its editor; verify the original meal ID is reused.
- Verify a replacement photo and a URL-imported photo use the corrected key.
- If RLS still rejects, collect the DEBUG IDs/path and deployed Storage policy definitions; do not infer missing policy from the local repository.
