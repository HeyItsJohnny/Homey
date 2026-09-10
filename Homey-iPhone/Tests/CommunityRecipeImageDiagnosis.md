# Community recipe image diagnosis

## Confirmed flow and fields

- Home image field: `meals.primary_photo_path`, passed to save_meal_recipe as requested_primary_photo_path.
- Community image field: `global_recipes.image_url`, passed to save_global_recipe as requested_image_url. The checked-in RPC stores the supplied text without resolving Storage paths.
- Bucket: `meal-images`.
- Object key: `<lowercase-home-id>/<lowercase-meal-id>/<lowercase-photo-uuid>.jpg`.
- Home stores the raw object key. Display generates a one-hour signed URL.
- Community currently receives draft.imported?.recipe.imageUrl. For a manual PhotosPicker photo this is nil, regardless of savedPhotoPath.

The iPhone order is already awaited: save Home, upload, attach the key to Home, then save Community. This is a missing payload reference, not a race. No temporary local image references are sent to the backend.

## iPad reference

GlobalMealsService builds requestedImageURL from draft.importedImageURL only. It does not map a selected local photo or primaryPhotoPath into the global payload. The iPad editor commits the global recipe before creating/updating the Home recipe and uploading a local image. Its shared global helper reuses imported/previously committed global IDs when available; otherwise it uses the same imported-image-only payload. It does not provide a proven local-photo contribution mechanism to copy into iPhone.

## Access-contract gap

ExploreRecipeImage only loads HTTP(S) URLs. iPad global image downloads also expect a URL. A raw Storage key would not render under the current contract. A permanently stored one-hour signed URL would expire. A public URL is usable only if meal-images is actually public; using signed URLs in Home does not establish the bucket's public/private setting.

No bucket definition or Storage policies are checked into this workspace. The user supplied deployed policies: authenticated SELECT/INSERT/UPDATE on meal-images require home_members.user_id = auth.uid() and home_members.home_id matching the first object-path folder; DELETE additionally requires owner/admin. These policies do not grant other Home members access to this Home’s images through authenticated Storage reads. The bucket public flag is still pending, so a durable shared reference cannot yet be selected. Requested read-only evidence:

```sql
SELECT id, public FROM storage.buckets WHERE id = 'meal-images';
SELECT policyname, roles, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'storage' AND tablename = 'objects';
```

If the existing bucket is public, the uploaded object can be referenced using its permanent public URL without uploading twice. If private, cross-Home access requires an established shared-image authorization mechanism; merely teaching iPhone to sign Home-scoped paths would not prove other Community users can access them. No bucket, policy, or privacy change is authorized/applied by this diagnostic work.

## Changes and status

Added DEBUG image-flow diagnostics at the actual Community payload boundary: Home ID, uploaded path, Home image value, and global payload. Editor passes its final savedPhotoPath after attachment succeeds. Source mapping and save behavior remain unchanged pending access evidence.

No-photo manual recipes still send nil. Imported recipes retain their remote source image URL. Retry retains savedHomeID, savedPhotoPath, and the selected-photo uploaded flag; no duplicate Home insert or image upload is added. Existing recipesRevision refresh remains unchanged.

The manual Community image bug is not claimed fixed. Live verification of manual photo ON/OFF, no-photo ON, imported photo ON, retry, and Explore image rendering remains pending the durable-reference fix.
