# Shared recipe editor verification

Create and Edit use RecipeEditorView with one card-based ScrollView, a mode-derived header and primary action, structured ingredient and numbered direction rows, and the existing save pipeline. The smaller-width layout stacks Meal Type and Source below 390 points and at accessibility text sizes. The keyboard has a Done action and interactive scroll dismissal.

All draft metadata is retained: name, description, meal types, cuisine, difficulty, prep/cook minutes, servings, source/name URL, notes, tags, ingredient quantity/unit/section/optional/preparation/notes, and step timers. Previously hidden recipe-level metadata is editable in Other details. Ingredient sections/optional/preparation/notes and timers remain preserved in the structured model.

## Verified

- iPhone simulator target builds.
- Production payload checks pass with read-only iPad contract fixtures.
- Edit prefill retains recipe metadata, ingredient details, and timers.
- Edited payload uses the existing recipe ID and unchanged photo path.
- Create defaults Community to ON; ON/OFF yields the same Home payload.
- Numeric/fraction quantities and invalid numeric quantities retain existing contract checks.
- Reviewed save guard, local validation, error retention, successful refresh/dismissal, and photo upload retry paths.
- Homey-iPad, Supabase, Explore, and Meal Planner source untouched in this UI task.

## Requires interactive/authenticated verification

Computer Use was not approved for Simulator. No successful live backend save or interactive device check is claimed.

- Small and Max portrait layouts, accessibility sizes, keyboard visibility and Done.
- Blank Create required-title disabled state; ingredient validation feedback.
- Create with no photo and with a selected photo, Community ON/OFF.
- PhotosPicker cancel/failure/replacement and signed existing photo display.
- Edit title, meal type, source, ingredients, directions, and photo; save to same record.
- Immediate list/detail refresh after an authenticated save.
- Backend failure leaves data and editor open; retry after photo/refresh failure.

## Existing backend limits

The save_global_recipe RPC inserts a new global recipe and accepts no existing recipe ID. Home globalRecipeId/originGlobalRecipeId references do not provide reliable current contribution/ownership state for this editor. Edit therefore preserves Home-only saving and shows explanatory text rather than an invented editable contribution switch. Create keeps the existing default-ON contribution switch. Editing does not re-contribute or update a global recipe.

Selected photos attach to the Home recipe through the existing private meal-images storage flow. Community publishing continues to use the existing imported remote image URL contract; this task does not publish signed/private Home photo URLs to Community.

There is no existing photo removal control, so the editor adds/selects/replaces photos without introducing storage deletion. Home and Community remain separate saves with the existing partial-save/retry semantics.
