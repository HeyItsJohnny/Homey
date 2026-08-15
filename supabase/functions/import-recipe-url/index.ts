import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import type { RecipeImportRequest, RecipeImportResponse } from "./types.ts";
import { corsHeaders, errorResponse, jsonResponse } from "./errors.ts";
import { RecipeImportError } from "./errors.ts";
import { normalizeRecipeUrl } from "./url_normalization.ts";
import { sha256Hex } from "./hash.ts";
import { fetchRecipePage } from "./fetch_page.ts";
import { extractRecipeJsonLd } from "./json_ld.ts";
import { normalizeSchemaRecipe, previewFromGlobalRecipe } from "./schema_recipe.ts";

type RecipeImportStatus = "processing" | "succeeded" | "failed";

interface ImportTrackingInput {
  homeId: string;
  userId: string;
  originalUrl: string;
  normalizedUrl: string;
  normalizedUrlHash: string;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  let importId: string | null = null;
  let serviceClient: SupabaseClient | null = null;

  try {
    if (request.method !== "POST") {
      throw new RecipeImportError("INVALID_URL", "Use POST to import a recipe URL.", 405);
    }

    const env = readSupabaseEnvironment();
    serviceClient = createClient(env.url, env.serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const userClient = createClient(env.url, env.anonKey, {
      global: { headers: { Authorization: request.headers.get("Authorization") ?? "" } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const user = await authenticatedUser(userClient);
    const payload = await parseRequest(request);
    await assertHomeMembership(serviceClient, payload.home_id, user.id);

    const normalized = normalizeRecipeUrl(payload.url);
    const normalizedUrlHash = await sha256Hex(normalized.normalizedUrl);
    debugLog("Normalized recipe URL", {
      domain: normalized.domain,
      normalizedUrl: normalized.normalizedUrl,
      normalizedUrlHash,
    });
    const trackingInput: ImportTrackingInput = {
      homeId: payload.home_id,
      userId: user.id,
      originalUrl: normalized.originalUrl,
      normalizedUrl: normalized.normalizedUrl,
      normalizedUrlHash,
    };

    const existingByUrl = await findExistingRecipeBySourceHash(serviceClient, normalizedUrlHash);
    if (existingByUrl) {
      debugLog("Existing global recipe matched by normalized URL hash", {
        globalRecipeId: String(existingByUrl.recipe.id),
      });
      importId = await createRecipeImport(serviceClient, trackingInput);
      await markRecipeImportSucceeded(serviceClient, importId, String(existingByUrl.recipe.id), true);
      return jsonResponse(responseFromRecords(importId, existingByUrl.recipe, existingByUrl.source, true));
    }

    importId = await createRecipeImport(serviceClient, trackingInput);

    const html = await fetchRecipePage(normalized.normalizedUrl);
    debugLog("Starting JSON-LD recipe extraction", normalized.domain);
    const recipeNode = extractRecipeJsonLd(html);
    debugLog("Starting Schema.org recipe normalization", null);
    const normalizedRecipe = await normalizeSchemaRecipe(recipeNode, normalized);
    debugLog("Normalized recipe preview", {
      title: normalizedRecipe.preview.title,
      ingredientCount: normalizedRecipe.preview.ingredients.length,
      stepCount: normalizedRecipe.preview.steps.length,
    });

    const duplicate = await findStrongDuplicate(
      serviceClient,
      normalized.domain,
      normalizedRecipe.sourceRecipeId,
      normalizedRecipe.recipeFingerprint,
    );

    let globalRecipeId: string;
    let alreadyExists = false;

    if (duplicate) {
      globalRecipeId = String(duplicate.id);
      alreadyExists = true;
    } else {
      globalRecipeId = await createGlobalRecipe(serviceClient, normalizedRecipe);
    }

    await createGlobalRecipeSource(serviceClient, {
      globalRecipeId,
      originalUrl: normalized.originalUrl,
      normalizedUrl: normalized.normalizedUrl,
      normalizedUrlHash,
      sourceDomain: normalized.domain,
      sourceName: normalizedRecipe.preview.source.name,
      sourceRecipeId: normalizedRecipe.sourceRecipeId,
    });

    await markRecipeImportSucceeded(serviceClient, importId, globalRecipeId, alreadyExists);

    const response: RecipeImportResponse = {
      importId,
      globalRecipeId,
      alreadyExists,
      normalizedUrl: normalized.normalizedUrl,
      recipe: {
        ...normalizedRecipe.preview,
        source: {
          ...normalizedRecipe.preview.source,
          originalUrl: normalized.originalUrl,
          normalizedUrl: normalized.normalizedUrl,
          domain: normalized.domain,
        },
      },
    };

    return jsonResponse(response);
  } catch (error) {
    if (serviceClient && importId) {
      await markRecipeImportFailed(serviceClient, importId, error);
    }

    debugLog("Recipe import failed", error);
    return errorResponse(error);
  }
});

function readSupabaseEnvironment(): { url: string; anonKey: string; serviceRoleKey: string } {
  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!url || !anonKey || !serviceRoleKey) {
    throw new RecipeImportError("INTERNAL_ERROR", "Recipe import is not configured.", 500);
  }

  return { url, anonKey, serviceRoleKey };
}

async function authenticatedUser(client: SupabaseClient): Promise<{ id: string }> {
  const { data, error } = await client.auth.getUser();
  if (error || !data.user) {
    throw new RecipeImportError("AUTH_REQUIRED", "Sign in before importing recipes.", 401);
  }

  return { id: data.user.id };
}

async function parseRequest(request: Request): Promise<RecipeImportRequest> {
  let payload: Partial<RecipeImportRequest>;
  try {
    payload = await request.json();
  } catch {
    throw new RecipeImportError("INVALID_RECIPE_DATA", "The recipe import request is invalid.");
  }

  if (!payload.home_id || !payload.url) {
    throw new RecipeImportError("INVALID_RECIPE_DATA", "Recipe import requires a Home and URL.");
  }

  return {
    home_id: payload.home_id,
    url: payload.url,
  };
}

async function assertHomeMembership(client: SupabaseClient, homeId: string, userId: string): Promise<void> {
  const { data, error } = await client
    .from("home_members")
    .select("user_id")
    .eq("home_id", homeId)
    .eq("user_id", userId)
    .maybeSingle();

  if (error) {
    debugSupabaseError("assertHomeMembership", error, { homeId, userId });
    throw new RecipeImportError("HOME_ACCESS_DENIED", "You do not have access to this Home.", 403);
  }

  if (!data) {
    throw new RecipeImportError("HOME_ACCESS_DENIED", "You do not have access to this Home.", 403);
  }
}

async function findExistingRecipeBySourceHash(
  client: SupabaseClient,
  normalizedUrlHash: string,
): Promise<{ source: Record<string, unknown>; recipe: Record<string, unknown> } | null> {
  const { data: source, error: sourceError } = await client
    .from("global_recipe_sources")
    .select("*")
    .eq("normalized_url_hash", normalizedUrlHash)
    .maybeSingle();

  if (sourceError) {
    debugSupabaseError("findExistingRecipeBySourceHash.source", sourceError, { normalizedUrlHash });
    throw new RecipeImportError("INTERNAL_ERROR", "We couldn't check this recipe source.", 500);
  }

  if (!source) {
    return null;
  }

  const recipe = await loadGlobalRecipe(client, String(source.global_recipe_id));
  return { source, recipe };
}

async function findStrongDuplicate(
  client: SupabaseClient,
  domain: string,
  sourceRecipeId: string | null,
  recipeFingerprint: string,
): Promise<Record<string, unknown> | null> {
  if (sourceRecipeId) {
    const { data: source, error } = await client
      .from("global_recipe_sources")
      .select("global_recipe_id")
      .eq("source_domain", domain)
      .eq("source_recipe_id", sourceRecipeId)
      .maybeSingle();

    if (error) {
      debugSupabaseError("findStrongDuplicate.sourceRecipeId", error, { domain, sourceRecipeId });
      throw new RecipeImportError("INTERNAL_ERROR", "We couldn't check this recipe source.", 500);
    }

    if (source) {
      return await loadGlobalRecipe(client, String(source.global_recipe_id));
    }
  }

  const { data: recipe, error } = await client
    .from("global_recipes")
    .select("*")
    .eq("recipe_fingerprint", recipeFingerprint)
    .maybeSingle();

  if (error) {
    debugSupabaseError("findStrongDuplicate.recipeFingerprint", error, { domain, recipeFingerprint });
    throw new RecipeImportError("INTERNAL_ERROR", "We couldn't check for existing recipes.", 500);
  }

  return recipe ?? null;
}

async function loadGlobalRecipe(client: SupabaseClient, globalRecipeId: string): Promise<Record<string, unknown>> {
  const { data, error } = await client
    .from("global_recipes")
    .select("*")
    .eq("id", globalRecipeId)
    .single();

  if (error || !data) {
    debugSupabaseError("loadGlobalRecipe", error, { globalRecipeId, missingData: !data });
    throw new RecipeImportError("INTERNAL_ERROR", "We couldn't load the imported recipe.", 500);
  }

  return data;
}

async function createRecipeImport(client: SupabaseClient, input: ImportTrackingInput): Promise<string> {
  const { data, error } = await client
    .from("recipe_imports")
    .insert({
      home_id: input.homeId,
      requested_by: input.userId,
      original_url: input.originalUrl,
      normalized_url: input.normalizedUrl,
      normalized_url_hash: input.normalizedUrlHash,
      status: "processing" satisfies RecipeImportStatus,
    })
    .select("id")
    .single();

  if (error || !data?.id) {
    debugSupabaseError("createRecipeImport", error, {
      homeId: input.homeId,
      userId: input.userId,
      normalizedUrlHash: input.normalizedUrlHash,
      missingImportId: !data?.id,
    });
    throw new RecipeImportError("INTERNAL_ERROR", "We couldn't start the recipe import.", 500);
  }

  return String(data.id);
}

async function markRecipeImportSucceeded(
  client: SupabaseClient,
  importId: string,
  globalRecipeId: string,
  alreadyExists: boolean,
): Promise<void> {
  const { error } = await client
    .from("recipe_imports")
    .update({
      global_recipe_id: globalRecipeId,
      already_exists: alreadyExists,
      status: "succeeded" satisfies RecipeImportStatus,
      completed_at: new Date().toISOString(),
      error_code: null,
      error_message: null,
    })
    .eq("id", importId);

  if (error) {
    debugSupabaseError("markRecipeImportSucceeded", error, { importId, globalRecipeId, alreadyExists });
  }
}

async function markRecipeImportFailed(client: SupabaseClient, importId: string, error: unknown): Promise<void> {
  const recipeError = error instanceof RecipeImportError
    ? error
    : new RecipeImportError("INTERNAL_ERROR", "We couldn't import this recipe right now.", 500);

  const { error: updateError } = await client
    .from("recipe_imports")
    .update({
      status: "failed" satisfies RecipeImportStatus,
      error_code: recipeError.code,
      error_message: recipeError.message,
      completed_at: new Date().toISOString(),
    })
    .eq("id", importId);

  if (updateError) {
    debugSupabaseError("markRecipeImportFailed", updateError, { importId, errorCode: recipeError.code });
  }
}

async function createGlobalRecipe(client: SupabaseClient, normalizedRecipe: Awaited<ReturnType<typeof normalizeSchemaRecipe>>): Promise<string> {
  const recipe = normalizedRecipe.preview;
  const { data, error } = await client
    .from("global_recipes")
    .insert({
      title: recipe.title,
      description: recipe.description,
      image_url: recipe.imageUrl,
      prep_time_minutes: recipe.prepTimeMinutes,
      cook_time_minutes: recipe.cookTimeMinutes,
      total_time_minutes: recipe.totalTimeMinutes,
      servings: recipe.servings,
      cuisine: recipe.cuisine,
      meal_types: recipe.mealTypes,
      keywords: recipe.keywords,
      ingredients: recipe.ingredients.map((ingredient) => ({
        section_name: ingredient.sectionName,
        ingredient_name: ingredient.ingredientName,
        quantity: ingredient.quantity,
        is_optional: ingredient.isOptional,
        sort_order: ingredient.sortOrder,
      })),
      steps: recipe.steps.map((step) => ({
        section_name: step.sectionName,
        step_text: step.stepText,
        sort_order: step.sortOrder,
      })),
      nutrition: recipe.nutrition,
      recipe_fingerprint: normalizedRecipe.recipeFingerprint,
      source_type: "url",
      status: "active",
      last_verified_at: new Date().toISOString(),
    })
    .select("id")
    .single();

  if (error || !data?.id) {
    debugSupabaseError("createGlobalRecipe", error, {
      title: recipe.title,
      recipeFingerprint: normalizedRecipe.recipeFingerprint,
      missingRecipeId: !data?.id,
    });
    throw new RecipeImportError("INTERNAL_ERROR", "We couldn't save the imported recipe.", 500);
  }

  return String(data.id);
}

async function createGlobalRecipeSource(
  client: SupabaseClient,
  input: {
    globalRecipeId: string;
    originalUrl: string;
    normalizedUrl: string;
    normalizedUrlHash: string;
    sourceDomain: string;
    sourceName: string | null;
    sourceRecipeId: string | null;
  },
): Promise<void> {
  const { error } = await client
    .from("global_recipe_sources")
    .insert({
      global_recipe_id: input.globalRecipeId,
      original_url: input.originalUrl,
      normalized_url: input.normalizedUrl,
      normalized_url_hash: input.normalizedUrlHash,
      source_domain: input.sourceDomain,
      source_name: input.sourceName,
      source_recipe_id: input.sourceRecipeId,
      is_primary: true,
      last_verified_at: new Date().toISOString(),
    });

  if (error) {
    debugSupabaseError("createGlobalRecipeSource", error, {
      globalRecipeId: input.globalRecipeId,
      normalizedUrlHash: input.normalizedUrlHash,
      sourceDomain: input.sourceDomain,
      sourceRecipeId: input.sourceRecipeId,
    });
    throw new RecipeImportError("INTERNAL_ERROR", "We couldn't save the recipe source.", 500);
  }
}

function responseFromRecords(
  importId: string,
  recipe: Record<string, unknown>,
  source: Record<string, unknown>,
  alreadyExists: boolean,
): RecipeImportResponse {
  return {
    importId,
    globalRecipeId: String(recipe.id),
    alreadyExists,
    normalizedUrl: String(source.normalized_url ?? ""),
    recipe: previewFromGlobalRecipe(recipe, source),
  };
}

function debugLog(message: string, value: unknown): void {
  const debugEnabled = Deno.env.get("DEBUG_RECIPE_IMPORT") === "true";
  if (!debugEnabled) {
    return;
  }

  console.log(`[import-recipe-url] ${message}`, value);
}

function debugSupabaseError(operation: string, error: unknown, context?: Record<string, unknown>): void {
  const debugEnabled = Deno.env.get("DEBUG_RECIPE_IMPORT") === "true";
  if (!debugEnabled) {
    return;
  }

  console.error(`[import-recipe-url] Supabase error in ${operation}`, {
    code: errorField(error, "code"),
    message: errorField(error, "message"),
    details: errorField(error, "details"),
    hint: errorField(error, "hint"),
    context,
  });
}

function errorField(error: unknown, field: "code" | "message" | "details" | "hint"): unknown {
  if (!error || typeof error !== "object") {
    return null;
  }

  return (error as Record<string, unknown>)[field] ?? null;
}
