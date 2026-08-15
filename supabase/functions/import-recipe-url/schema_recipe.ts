import type {
  ImportedRecipeIngredient,
  ImportedRecipePreview,
  ImportedRecipeSource,
  ImportedRecipeStep,
  RecipeImportJSONValue,
} from "./types.ts";
import { cleanText, firstRawString, firstString, isJsonObject, type JsonObject, type JsonValue, stringArray } from "./json_ld.ts";
import type { NormalizedRecipeURL } from "./url_normalization.ts";
import { sha256Hex } from "./hash.ts";
import { RecipeImportError } from "./errors.ts";

const supportedMealTypes = new Set(["breakfast", "lunch", "dinner", "snack"]);

export interface NormalizedRecipe {
  preview: ImportedRecipePreview;
  sourceRecipeId: string | null;
  recipeFingerprint: string;
}

export async function normalizeSchemaRecipe(recipeNode: JsonObject, sourceUrl: NormalizedRecipeURL): Promise<NormalizedRecipe> {
  const title = firstString(recipeNode.name);
  if (!title) {
    throw new RecipeImportError("INVALID_RECIPE_DATA", "The recipe data on this page is missing a title.", 422);
  }

  const ingredients = normalizeIngredients(recipeNode.recipeIngredient);
  if (ingredients.length === 0) {
    throw new RecipeImportError("INVALID_RECIPE_DATA", "The recipe data on this page is missing ingredients.", 422);
  }

  const steps = normalizeInstructions(recipeNode.recipeInstructions);
  const source = normalizeSource(recipeNode, sourceUrl);
  const mealTypes = mapMealTypes(recipeNode.recipeCategory);
  const keywords = uniqueStrings([
    ...stringArray(recipeNode.keywords),
    ...stringArray(recipeNode.recipeCategory).filter((category) => !supportedMealTypes.has(category.toLowerCase())),
  ]);

  const preview: ImportedRecipePreview = {
    title,
    description: firstString(recipeNode.description),
    imageUrl: normalizeImage(recipeNode.image),
    prepTimeMinutes: parseISODurationMinutes(firstString(recipeNode.prepTime)),
    cookTimeMinutes: parseISODurationMinutes(firstString(recipeNode.cookTime)),
    totalTimeMinutes: parseISODurationMinutes(firstString(recipeNode.totalTime)),
    servings: firstString(recipeNode.recipeYield),
    cuisine: firstString(recipeNode.recipeCuisine),
    mealTypes,
    keywords,
    ingredients,
    steps,
    nutrition: jsonValueForResponse(recipeNode.nutrition),
    source,
  };

  return {
    preview,
    sourceRecipeId: sourceRecipeId(recipeNode),
    recipeFingerprint: await recipeFingerprint(preview, sourceUrl.domain),
  };
}

export function previewFromGlobalRecipe(recipe: Record<string, unknown>, source: Record<string, unknown>): ImportedRecipePreview {
  return {
    title: cleanRecordString(recipe, "title") ?? "Imported Recipe",
    description: nullableCleanRecordString(recipe, "description"),
    imageUrl: nullableStringFromRecord(recipe, "image_url"),
    prepTimeMinutes: nullableNumberFromRecord(recipe, "prep_time_minutes"),
    cookTimeMinutes: nullableNumberFromRecord(recipe, "cook_time_minutes"),
    totalTimeMinutes: nullableNumberFromRecord(recipe, "total_time_minutes"),
    servings: nullableCleanRecordString(recipe, "servings"),
    cuisine: nullableCleanRecordString(recipe, "cuisine"),
    mealTypes: stringArrayFromRecord(recipe, "meal_types"),
    keywords: stringArrayFromRecord(recipe, "keywords").map(cleanText).filter(Boolean),
    ingredients: importedIngredientArray(recipe.ingredients),
    steps: importedStepArray(recipe.steps),
    nutrition: jsonValueForResponse(recipe.nutrition as JsonValue | undefined),
    source: {
      originalUrl: stringFromRecord(source, "original_url") ?? "",
      normalizedUrl: stringFromRecord(source, "normalized_url") ?? "",
      domain: stringFromRecord(source, "source_domain") ?? "",
      name: nullableCleanRecordString(source, "source_name"),
    },
  };
}

function normalizeIngredients(value: JsonValue | undefined): ImportedRecipeIngredient[] {
  return stringArray(value).map((ingredientName, index) => ({
    sectionName: null,
    ingredientName,
    quantity: null,
    isOptional: false,
    sortOrder: index,
  }));
}

function normalizeInstructions(value: JsonValue | undefined, sectionName: string | null = null): ImportedRecipeStep[] {
  if (!value) {
    return [];
  }

  if (typeof value === "string") {
    const stepText = cleanText(value);
    return stepText ? [{ sectionName, stepText, sortOrder: 0 }] : [];
  }

  if (Array.isArray(value)) {
    return value
      .flatMap((item) => normalizeInstructions(item, sectionName))
      .map((step, index) => ({ ...step, sortOrder: index }));
  }

  if (!isJsonObject(value)) {
    return [];
  }

  const type = firstString(value["@type"])?.toLowerCase();
  if (type === "howtosection") {
    const nestedSectionName = firstString(value.name) ?? sectionName;
    return normalizeInstructions(value.itemListElement ?? value.steps, nestedSectionName)
      .map((step, index) => ({ ...step, sortOrder: index }));
  }

  if (type === "howtostep" || value.text || value.name) {
    const stepText = firstString(value.text) ?? firstString(value.name);
    return stepText ? [{ sectionName, stepText, sortOrder: 0 }] : [];
  }

  return normalizeInstructions(value.itemListElement, sectionName);
}

function normalizeImage(value: JsonValue | undefined): string | null {
  if (typeof value === "string") {
    return firstRawString(value);
  }

  if (Array.isArray(value)) {
    for (const item of value) {
      const image = normalizeImage(item);
      if (image) {
        return image;
      }
    }
  }

  if (isJsonObject(value)) {
    return firstRawString(value.url) ?? firstRawString(value.contentUrl);
  }

  return null;
}

function normalizeSource(recipeNode: JsonObject, sourceUrl: NormalizedRecipeURL): ImportedRecipeSource {
  return {
    originalUrl: sourceUrl.originalUrl,
    normalizedUrl: firstRawString(recipeNode.url) ?? sourceUrl.normalizedUrl,
    domain: sourceUrl.domain,
    name: sourceName(sourceUrl.domain),
  };
}

function sourceName(domain: string): string {
  const core = domain.split(".").slice(-2, -1)[0] ?? domain;
  return core
    .replace(/[-_]+/g, " ")
    .replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function sourceRecipeId(recipeNode: JsonObject): string | null {
  return firstRawString(recipeNode.identifier) ??
    firstRawString(recipeNode["@id"]) ??
    firstRawString(recipeNode.mainEntityOfPage);
}

function mapMealTypes(value: JsonValue | undefined): string[] {
  const categories = stringArray(value).map((category) => category.toLowerCase());
  const mapped = new Set<string>();

  for (const category of categories) {
    if (category.includes("breakfast") || category.includes("brunch")) {
      mapped.add("breakfast");
    }
    if (category.includes("lunch")) {
      mapped.add("lunch");
    }
    if (category.includes("dinner") || category.includes("supper") || category.includes("main dish") || category.includes("main course")) {
      mapped.add("dinner");
    }
    if (category.includes("snack") || category.includes("appetizer")) {
      mapped.add("snack");
    }
  }

  return [...mapped];
}

export function parseISODurationMinutes(value: string | null): number | null {
  if (!value) {
    return null;
  }

  const match = value.trim().match(/^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$/i);
  if (!match) {
    return null;
  }

  const days = Number(match[1] ?? 0);
  const hours = Number(match[2] ?? 0);
  const minutes = Number(match[3] ?? 0);
  const seconds = Number(match[4] ?? 0);
  return days * 24 * 60 + hours * 60 + minutes + (seconds > 0 ? Math.ceil(seconds / 60) : 0);
}

async function recipeFingerprint(recipe: ImportedRecipePreview, domain: string): Promise<string> {
  const normalizedIngredients = recipe.ingredients
    .map((ingredient) => normalizeForFingerprint(ingredient.ingredientName))
    .join("|");
  const seed = [
    normalizeForFingerprint(recipe.title),
    normalizeForFingerprint(domain),
    normalizedIngredients,
  ].join("::");
  return await sha256Hex(seed);
}

function normalizeForFingerprint(value: string): string {
  return value
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function uniqueStrings(values: string[]): string[] {
  return [...new Set(values.map((value) => cleanText(value)).filter(Boolean))];
}

function jsonValueForResponse(value: unknown): RecipeImportJSONValue | null {
  if (value === null || value === undefined) {
    return null;
  }
  if (typeof value === "string" || typeof value === "number" || typeof value === "boolean") {
    return value;
  }
  if (Array.isArray(value)) {
    return value.map(jsonValueForResponse).filter((item): item is RecipeImportJSONValue => item !== null);
  }
  if (typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>)
        .map(([key, nestedValue]) => [key, jsonValueForResponse(nestedValue)])
        .filter((entry): entry is [string, RecipeImportJSONValue] => entry[1] !== null),
    );
  }
  return null;
}

function stringFromRecord(record: Record<string, unknown>, key: string): string | null {
  const value = record[key];
  return typeof value === "string" ? value : null;
}

function nullableStringFromRecord(record: Record<string, unknown>, key: string): string | null {
  return stringFromRecord(record, key);
}

function cleanRecordString(record: Record<string, unknown>, key: string): string | null {
  const value = stringFromRecord(record, key);
  return value ? cleanText(value) : null;
}

function nullableCleanRecordString(record: Record<string, unknown>, key: string): string | null {
  return cleanRecordString(record, key);
}

function nullableNumberFromRecord(record: Record<string, unknown>, key: string): number | null {
  const value = record[key];
  return typeof value === "number" ? value : null;
}

function stringArrayFromRecord(record: Record<string, unknown>, key: string): string[] {
  const value = record[key];
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

function importedIngredientArray(value: unknown): ImportedRecipeIngredient[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.map((item, index) => {
    const object = typeof item === "object" && item !== null ? item as Record<string, unknown> : {};
    return {
      sectionName: nullableCleanRecordString(object, "sectionName") ?? nullableCleanRecordString(object, "section_name"),
      ingredientName: cleanText(stringFromRecord(object, "ingredientName") ?? stringFromRecord(object, "ingredient_name") ?? String(item)),
      quantity: nullableCleanRecordString(object, "quantity"),
      isOptional: object.isOptional === true || object.is_optional === true,
      sortOrder: nullableNumberFromRecord(object, "sortOrder") ?? nullableNumberFromRecord(object, "sort_order") ?? index,
    };
  });
}

function importedStepArray(value: unknown): ImportedRecipeStep[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.map((item, index) => {
    const object = typeof item === "object" && item !== null ? item as Record<string, unknown> : {};
    return {
      sectionName: nullableCleanRecordString(object, "sectionName") ?? nullableCleanRecordString(object, "section_name"),
      stepText: cleanText(stringFromRecord(object, "stepText") ?? stringFromRecord(object, "step_text") ?? String(item)),
      sortOrder: nullableNumberFromRecord(object, "sortOrder") ?? nullableNumberFromRecord(object, "sort_order") ?? index,
    };
  });
}
