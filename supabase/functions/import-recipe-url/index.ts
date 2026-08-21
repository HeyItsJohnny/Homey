import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import type { RecipeImportRequest, RecipeImportResponse } from "./types.ts";
import { corsHeaders, errorResponse, jsonResponse } from "./errors.ts";
import { RecipeImportError } from "./errors.ts";
import { normalizeRecipeUrl } from "./url_normalization.ts";
import { sha256Hex } from "./hash.ts";
import { fetchRecipePage } from "./fetch_page.ts";
import { extractRecipeJsonLd } from "./json_ld.ts";
import { normalizeSchemaRecipe } from "./schema_recipe.ts";

type RecipeImportStatus = "processing" | "succeeded" | "failed";
const pipelineVersion = "parse-preview-v2";

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
  let stage = "request";

  try {
    console.log("========== RECIPE IMPORT ==========", {
      stage: "request_received",
      pipeline_version: pipelineVersion,
    });

    stage = "method";
    if (request.method !== "POST") {
      throw new RecipeImportError("INVALID_URL", "Use POST to import a recipe URL.", 405);
    }

    stage = "configure";
    const env = readSupabaseEnvironment();
    serviceClient = createClient(env.url, env.serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const userClient = createClient(env.url, env.anonKey, {
      global: { headers: { Authorization: request.headers.get("Authorization") ?? "" } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    stage = "auth";
    const user = await authenticatedUser(userClient);
    stage = "parse-request";
    const payload = await parseRequest(request);
    stage = "home-membership";
    await assertHomeMembership(serviceClient, payload.home_id, user.id);

    stage = "normalize-url";
    const normalized = normalizeRecipeUrl(payload.url);
    const normalizedUrlHash = await sha256Hex(normalized.normalizedUrl);
    console.log("========== RECIPE IMPORT ==========", {
      stage: "url_normalized",
      pipeline_version: pipelineVersion,
      domain: normalized.domain,
      normalized_url_hash: normalizedUrlHash,
    });
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

    stage = "recipe-imports.insert";
    importId = await createRecipeImport(serviceClient, trackingInput);

    stage = "fetch";
    const html = await fetchRecipePage(normalized.normalizedUrl);
    console.log("========== RECIPE IMPORT ==========", {
      stage: "source_fetched",
      pipeline_version: pipelineVersion,
      byte_length: html.length,
    });
    debugLog("Starting JSON-LD recipe extraction", normalized.domain);
    stage = "parse-json-ld";
    const recipeNode = extractRecipeJsonLd(html);
    console.log("========== RECIPE IMPORT ==========", {
      stage: "recipe_parsed",
      pipeline_version: pipelineVersion,
    });
    debugLog("Starting Schema.org recipe normalization", null);
    stage = "normalize-recipe";
    const normalizedRecipe = await normalizeSchemaRecipe(recipeNode, normalized);
    console.log("========== RECIPE IMPORT ==========", {
      stage: "recipe_normalized",
      pipeline_version: pipelineVersion,
      ingredient_count: normalizedRecipe.preview.ingredients.length,
      step_count: normalizedRecipe.preview.steps.length,
    });
    debugLog("Normalized recipe preview", {
      title: normalizedRecipe.preview.title,
      ingredientCount: normalizedRecipe.preview.ingredients.length,
      stepCount: normalizedRecipe.preview.steps.length,
    });

    stage = "recipe_imports.update-succeeded";
    await markRecipeImportSucceeded(serviceClient, importId, null, false);

    stage = "response";
    console.log("========== RECIPE IMPORT ==========", {
      stage: "returning_preview",
      pipeline_version: pipelineVersion,
      global_recipe_created: false,
      global_recipe_source_created: false,
    });
    const response: RecipeImportResponse = {
      importId,
      globalRecipeId: null,
      alreadyExists: false,
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

    logRecipeImportFailure(stage, error, { importId });
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
    logSupabaseError("assertHomeMembership", error, { homeId, userId });
    throw new RecipeImportError("HOME_ACCESS_DENIED", "You do not have access to this Home.", 403);
  }

  if (!data) {
    throw new RecipeImportError("HOME_ACCESS_DENIED", "You do not have access to this Home.", 403);
  }
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
    logSupabaseError("createRecipeImport", error, {
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
  globalRecipeId: string | null,
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
    logSupabaseError("markRecipeImportSucceeded", error, { importId, globalRecipeId, alreadyExists });
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
    logSupabaseError("markRecipeImportFailed", updateError, { importId, errorCode: recipeError.code });
  }
}

function debugLog(message: string, value: unknown): void {
  const debugEnabled = Deno.env.get("DEBUG_RECIPE_IMPORT") === "true";
  if (!debugEnabled) {
    return;
  }

  console.log(`[import-recipe-url] ${message}`, value);
}

function logRecipeImportFailure(stage: string, error: unknown, context?: Record<string, unknown>): void {
  console.error("========== RECIPE IMPORT FAILED ==========", {
    stage,
    error_type: errorType(error),
    code: errorField(error, "code"),
    message: errorField(error, "message"),
    details: errorField(error, "details"),
    hint: errorField(error, "hint"),
    constraint: errorField(error, "constraint"),
    status: errorField(error, "status"),
    stack: errorStack(error),
    context,
  });
}

function logSupabaseError(operation: string, error: unknown, context?: Record<string, unknown>): void {
  console.error(`[import-recipe-url] Supabase error in ${operation}`, {
    operation,
    error_type: errorType(error),
    code: errorField(error, "code"),
    message: errorField(error, "message"),
    details: errorField(error, "details"),
    hint: errorField(error, "hint"),
    constraint: errorField(error, "constraint"),
    status: errorField(error, "status"),
    stack: errorStack(error),
    context,
  });
}

function errorField(error: unknown, field: "code" | "message" | "details" | "hint" | "constraint" | "status"): unknown {
  if (!error || typeof error !== "object") {
    return null;
  }

  return (error as Record<string, unknown>)[field] ?? null;
}

function errorType(error: unknown): string {
  if (error instanceof Error) {
    return error.name;
  }

  return typeof error;
}

function errorStack(error: unknown): string | null {
  if (error instanceof Error) {
    return error.stack ?? null;
  }

  return null;
}
