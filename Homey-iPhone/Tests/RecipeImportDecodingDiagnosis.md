# Import decoder correction

## Reproduced failure

Downloaded https://www.frontrangefed.com/sheet-pan-pancakes-from-mix/ and ran the checked-in JSON-LD extractor, URL normalizer, and Schema.org normalizer locally. Used html-entities 2.5.2, the exact parser dependency, in a temporary Node harness. Only the temporary module import was adapted from the Deno HTTPS import; repository parser files were untouched. The harness made no Supabase calls. The fixture uses a synthetic importId and the actual extracted preview.

The old iPhone ingredient DTO reproduces:

- DecodingError.keyNotFound
- missingKey=sort_order
- codingPath=recipe.ingredients[0]
- debugDescription=No value associated with key CodingKeys(stringValue: "sort_order", intValue: nil) ("sort_order").

The parser returned camelCase sortOrder. Other affected fields were ingredientName/isOptional/sectionName and stepText/sortOrder/sectionName. These are confirmed against local production-parser output; the historical deployed HTTP response has not been captured. Added runtime diagnostics will capture future responses before decode.

## Contract comparison

| Field | iPhone before | iPad / corrected iPhone |
| --- | --- | --- |
| Envelope | importId, globalRecipeId?, alreadyExists, normalizedUrl, recipe | Same; no data envelope |
| Ingredients | CommunityIngredient with snake_case database CodingKeys | ImportedRecipeIngredient with camelCase preview properties |
| Ingredient required fields | ingredient_name, is_optional, sort_order | ingredientName: String, isOptional: Bool, sortOrder: Int |
| Ingredient optional fields | section_name, quantity | sectionName: String?, quantity: String? |
| Steps | CommunityStep with snake_case database CodingKeys | ImportedRecipeStep with camelCase stepText: String, sortOrder: Int, sectionName: String? |
| Title | String required | Same |
| Image | imageUrl: String? | Same |
| Description/cuisine/servings | String? | Same; servings stays a string in the network DTO |
| Prep/cook/total | Int? | Same; no arbitrary numeric coercion added |
| Source | originalUrl/normalizedUrl/domain required; name optional | Same |
| Meal types | String array | iPad uses MealType array; iPhone retains its existing string-to-MealType draft mapping |
| Nutrition | Not modeled | iPad has optional JSON nutrition; iPhone still ignores this unsupported editor metadata |
| Author/notes | Not supplied by preview DTO | No invented fields |

Community database DTOs remain unchanged for database/save payloads. Import DTOs are separate. The shared RecipeDraft mapping now receives the correct structured ingredient/step types; image/source/missing-metadata behavior is retained.

## Response logging and classification

Uses the installed Supabase FunctionsClient.invoke decode closure to receive Data + HTTPURLResponse, preserving the existing network layer. DEBUG logs status, content type, and response JSON before decoding. Sensitive keys and URL credentials/query/fragment values are redacted while field names, structure, and value types otherwise remain visible. Unstructured non-JSON bodies are reported by byte count rather than risking secret logging.

Detailed DecodingError diagnostics cover keyNotFound, valueNotFound, typeMismatch, dataCorrupted, coding path, missing key/expected type, context debugDescription, and underlying error domain/code.

Non-2xx FunctionsError bodies retain backend error codes. A recognized error envelope on 2xx is checked before success decoding. SOURCE_BLOCKED and parser failures remain distinct. URLError becomes NETWORK_ERROR; decoding errors become RESPONSE_DECODING_ERROR and no longer advise checking the connection. Other request errors remain IMPORT_REQUEST_ERROR/HTTP status codes.

## Verification

- Old decoder failure reproduced against exact-page parser output.
- Corrected decoder and draft mapping: Sheet Pan Pancakes From Mix, image present, six ingredients, six directions, original source URL retained.
- Optional metadata omitted: image, description, servings, prep/cook/total, and cuisine all decode without failing recipe content.
- SOURCE_BLOCKED fixture recognized as backend error, not successful recipe/decoding error.
- Malformed URL and safe-log redaction tests pass.
- Existing save payload, edit, image-path, source-type, and retry tests pass.
- iPhone simulator-target build passes.

Live authenticated URL-sheet/editor presentation and a separately confirmed working iPad URL remain unverified. SOURCE_BLOCKED/no-image regressions use fixtures, not live blocked/no-image website claims.

## Database and scope

No iPad or Supabase Edge Function/schema files were changed. This fix adds no Home/global/ingredient/favorite/planner/image persistence during import. No Supabase call was used in the local reproduction.

The pre-existing Edge Function still writes recipe_imports tracking rows; the earlier preview-only patch remains unapplied. A strict claim that live import performs zero database writes before Save would be false. This decoding fix leaves that separate backend issue unchanged.

Files changed: MealsModels.swift, MealsService.swift, RecipeImportSupport.swift, RecipeImportDiagnostics.swift (new), RecipeSaveContractChecks.swift, run-recipe-save-checks.py, Fixtures/front-range-fed-import.json, and this diagnosis.
