# Community source-type constraint fix

The supplied error was PostgreSQL 23514 on global_recipes_source_type_check after Home save and image upload succeeded for a manual recipe, Ube Pancakes.

The user supplied the deployed constraint. It allows exactly: `url`, `instagram`, `community`, `variation`. It does not allow `manual`.

## Mapping

| Flow | iPhone before | iPhone fixed | iPad reference (unchanged) |
| --- | --- | --- | --- |
| Manual contribution | `manual` | `community` | `manual` |
| URL-import contribution | `url` | `url` | `url` |
| Home-only save | No Community RPC | Unchanged | No contribution |

CommunityRecipeSourceType centralizes the two types this editor produces. Instagram imports and variations are not created by this editor. The iPhone retains save_global_recipe and its existing argument structure.

The iPad reference and checked-in RPC default (`manual` for blank values) conflict with the deployed constraint. The iPhone now explicitly supplies a valid value. No SQL change is required for this client fix; iPad and SQL remain untouched.

## Payload details

- Source name and source URL are trimmed draft fields, sent as null if blank. There is no separate `source` RPC parameter.
- Imported drafts populate the URL from the import response's original URL. Imported status is used client-side, not sent as a separate boolean.
- Existing image/title/description/times/servings/cuisine/meal types/tags/ingredients/steps arguments are unchanged.
- The authenticated session identifies the caller. No creator ID is sent. The checked-in RPC validates auth.uid() but does not explicitly insert created_by; the table's default/trigger behavior is unavailable locally.
- No normalized_url argument is sent. The checked-in RPC stores the trimmed source URL as original_url and normalized_url, with md5 of its lowercase form. This existing behavior was not changed.
- DEBUG logs immediately before the RPC report sourceType, source, sourceURL, and imported. No authentication tokens or keys are logged.

## Partial save behavior

Home recipe and image remain saved when Community fails. The editor reports partial success and stays open. Retry uses savedHomeID and savedPhotoPath, and a selected photo that already uploaded is not uploaded again. This prevents a new Home insert during retry within the same editor session; closing the editor loses that in-memory retry state. No destructive rollback was added.

## Verification

Production contract checks verify manual `community`, imported `url`, Community-independent Home payloads, and retained retry ID/photo path. The fixture uses read-only iPad RPC parameter types with the deployed constraint's corrected manual value.

Live acceptance checks still required:

- Manual / Community OFF: Home save succeeds.
- Manual / Community ON: Home and Community save succeed; DEBUG sourceType=community.
- Imported / Community ON: Community save succeeds; DEBUG sourceType=url.
- Retry after Community failure: original Home ID and image retained, no second Home record.

A successful build and payload tests do not prove live server acceptance. No live successful manual/imported Community save is claimed.
