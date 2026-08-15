import { RecipeImportError } from "./errors.ts";
import { cleanText, decodeHtmlEntities } from "./text_normalization.ts";

export type JsonObject = { [key: string]: JsonValue };
export type JsonValue = string | number | boolean | null | JsonObject | JsonValue[];

export function extractRecipeJsonLd(html: string): JsonObject {
  const scripts = extractJsonLdScripts(html);
  debugLog("JSON-LD script count", scripts.length);
  let parseableBlocks = 0;
  let recipeNodesFound = 0;

  for (const script of scripts) {
    const parsed = parseJsonLeniently(script);
    if (parsed === null) {
      continue;
    }

    parseableBlocks += 1;
    const recipe = findRecipeNode(parsed);
    if (recipe) {
      recipeNodesFound += 1;
      debugLog("JSON-LD parseable blocks", parseableBlocks);
      debugLog("Recipe nodes found", recipeNodesFound);
      debugLog("Selected recipe node name", firstString(recipe.name) ?? firstString(recipe.headline) ?? "<untitled>");
      return recipe;
    }
  }

  debugLog("JSON-LD parseable blocks", parseableBlocks);
  debugLog("Recipe nodes found", recipeNodesFound);
  throw new RecipeImportError("NO_RECIPE_FOUND", "We couldn't find recipe information on this page.", 422);
}

function extractJsonLdScripts(html: string): string[] {
  const scripts: string[] = [];
  const scriptRegex = /<script\b([^>]*)>([\s\S]*?)<\/script>/gi;
  let match: RegExpExecArray | null;

  while ((match = scriptRegex.exec(html)) !== null) {
    const attributes = match[1] ?? "";
    if (/type\s*=\s*["']application\/ld\+json["']/i.test(attributes)) {
      scripts.push(stripHtmlComments(match[2] ?? "").trim());
    }
  }

  return scripts;
}

function parseJsonLeniently(text: string): JsonValue {
  try {
    return JSON.parse(text) as JsonValue;
  } catch {
    const trimmed = decodeHtmlEntities(text)
      .replace(/^\uFEFF/, "")
      .trim();

    try {
      return JSON.parse(trimmed) as JsonValue;
    } catch {
      return null;
    }
  }
}

function findRecipeNode(value: JsonValue): JsonObject | null {
  if (Array.isArray(value)) {
    for (const item of value) {
      const found = findRecipeNode(item);
      if (found) {
        return found;
      }
    }
    return null;
  }

  if (!isJsonObject(value)) {
    return null;
  }

  if (isRecipeType(value["@type"])) {
    return value;
  }

  const graph = value["@graph"];
  if (graph) {
    const graphMatch = findRecipeNode(graph);
    if (graphMatch) {
      return graphMatch;
    }
  }

  for (const nestedValue of Object.values(value)) {
    const found = findRecipeNode(nestedValue);
    if (found) {
      return found;
    }
  }

  return null;
}

function isRecipeType(value: JsonValue | undefined): boolean {
  if (typeof value === "string") {
    return value.toLowerCase() === "recipe";
  }

  if (Array.isArray(value)) {
    return value.some((item) => typeof item === "string" && item.toLowerCase() === "recipe");
  }

  return false;
}

export function isJsonObject(value: JsonValue | undefined): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function firstString(value: JsonValue | undefined): string | null {
  if (typeof value === "string") {
    return cleanText(value);
  }

  if (typeof value === "number" || typeof value === "boolean") {
    return String(value);
  }

  if (Array.isArray(value)) {
    for (const item of value) {
      const result = firstString(item);
      if (result) {
        return result;
      }
    }
  }

  if (isJsonObject(value)) {
    return firstString(value.name) ?? firstString(value.url) ?? firstString(value["@id"]);
  }

  return null;
}

export function firstRawString(value: JsonValue | undefined): string | null {
  if (typeof value === "string") {
    const trimmed = value.trim();
    return trimmed || null;
  }

  if (typeof value === "number" || typeof value === "boolean") {
    return String(value);
  }

  if (Array.isArray(value)) {
    for (const item of value) {
      const result = firstRawString(item);
      if (result) {
        return result;
      }
    }
  }

  if (isJsonObject(value)) {
    return firstRawString(value.url) ?? firstRawString(value["@id"]);
  }

  return null;
}

export function stringArray(value: JsonValue | undefined): string[] {
  if (Array.isArray(value)) {
    return value.flatMap((item) => {
      const result = firstString(item);
      return result ? [result] : [];
    });
  }

  const single = firstString(value);
  if (!single) {
    return [];
  }

  return single
    .split(",")
    .map((item) => cleanText(item))
    .filter(Boolean);
}

function stripHtmlComments(value: string): string {
  return value.replace(/<!--|-->/g, "");
}

function debugLog(message: string, value: unknown): void {
  if (Deno.env.get("DEBUG_RECIPE_IMPORT") !== "true") {
    return;
  }

  console.log(`[import-recipe-url] ${message}:`, value);
}
