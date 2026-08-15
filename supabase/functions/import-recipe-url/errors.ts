import type { RecipeImportAPIErrorCode } from "./types.ts";

export class RecipeImportError extends Error {
  readonly code: RecipeImportAPIErrorCode;
  readonly status: number;

  constructor(code: RecipeImportAPIErrorCode, message: string, status = 400) {
    super(message);
    this.name = "RecipeImportError";
    this.code = code;
    this.status = status;
  }
}

export function errorResponse(error: unknown): Response {
  const recipeError = error instanceof RecipeImportError
    ? error
    : new RecipeImportError("INTERNAL_ERROR", "Homey couldn't import this recipe.", 500);

  return jsonError(recipeError.code, recipeError.message, recipeError.status);
}

export function jsonError(code: RecipeImportAPIErrorCode, message: string, status: number): Response {
  return jsonResponse({ error: { code, message } }, status);
}

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...corsHeaders,
    },
  });
}

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
