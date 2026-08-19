import { RecipeImportError } from "./errors.ts";

const trackingQueryKeys = new Set([
  "utm_source",
  "utm_medium",
  "utm_campaign",
  "utm_term",
  "utm_content",
  "utm_id",
  "utm_source_platform",
  "utm_creative_format",
  "utm_marketing_tactic",
  "fbclid",
  "gclid",
  "dclid",
  "gbraid",
  "wbraid",
  "mc_cid",
  "mc_eid",
]);

const blockedHosts = new Set(["localhost", "localhost.localdomain"]);

export interface NormalizedRecipeURL {
  originalUrl: string;
  normalizedUrl: string;
  domain: string;
}

export function normalizeRecipeUrl(rawUrl: string): NormalizedRecipeURL {
  let parsed: URL;
  try {
    parsed = new URL(rawUrl.trim());
  } catch {
    throw new RecipeImportError("INVALID_URL", "Enter a valid recipe URL.");
  }

  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
    throw new RecipeImportError("INVALID_URL", "Recipe URLs must start with http or https.");
  }

  assertPublicHostname(parsed.hostname);

  parsed.protocol = parsed.protocol.toLowerCase();
  parsed.hostname = normalizeHost(parsed.hostname);
  parsed.hash = "";

  for (const key of [...parsed.searchParams.keys()]) {
    const lowerKey = key.toLowerCase();
    if (trackingQueryKeys.has(lowerKey) || lowerKey.startsWith("utm_") || isTrackingRefParam(lowerKey, parsed.searchParams.get(key))) {
      parsed.searchParams.delete(key);
    }
  }

  parsed.searchParams.sort();

  if ((parsed.protocol === "https:" && parsed.port === "443") || (parsed.protocol === "http:" && parsed.port === "80")) {
    parsed.port = "";
  }

  let normalizedUrl = parsed.toString();
  if (parsed.pathname === "/" && !parsed.search) {
    normalizedUrl = normalizedUrl.replace(/\/$/, "");
  }

  return {
    originalUrl: rawUrl.trim(),
    normalizedUrl,
    domain: parsed.hostname,
  };
}

function normalizeHost(host: string): string {
  const lowerHost = host.toLowerCase();
  if (lowerHost.startsWith("www.")) {
    return lowerHost.slice(4);
  }
  return lowerHost;
}

function isTrackingRefParam(key: string, value: string | null): boolean {
  if (key !== "ref") {
    return false;
  }

  if (!value) {
    return true;
  }

  const normalizedValue = value.toLowerCase();
  return [
    "social",
    "email",
    "newsletter",
    "facebook",
    "instagram",
    "twitter",
    "pinterest",
    "homepage",
    "feed",
  ].some((trackingValue) => normalizedValue.includes(trackingValue));
}

function assertPublicHostname(hostname: string): void {
  const normalized = hostname.toLowerCase();
  if (blockedHosts.has(normalized) || normalized.endsWith(".local")) {
    debugLog("Source policy blocked hostname", { hostname: normalized, reason: "local_hostname" });
    throw new RecipeImportError("SOURCE_BLOCKED", "This recipe source is not allowed.");
  }

  if (/^\d+\.\d+\.\d+\.\d+$/.test(normalized) && isPrivateIPv4(normalized)) {
    debugLog("Source policy blocked hostname", { hostname: normalized, reason: "private_ipv4" });
    throw new RecipeImportError("SOURCE_BLOCKED", "This recipe source is not allowed.");
  }

  if (normalized === "::1" || normalized.startsWith("[::1]")) {
    debugLog("Source policy blocked hostname", { hostname: normalized, reason: "loopback_ipv6" });
    throw new RecipeImportError("SOURCE_BLOCKED", "This recipe source is not allowed.");
  }

  debugLog("Source policy allowed hostname", { hostname: normalized });
}

function isPrivateIPv4(ipAddress: string): boolean {
  const parts = ipAddress.split(".").map((part) => Number(part));
  if (parts.length !== 4 || parts.some((part) => Number.isNaN(part) || part < 0 || part > 255)) {
    return true;
  }

  const [first, second] = parts;
  return first === 10 ||
    first === 127 ||
    (first === 172 && second >= 16 && second <= 31) ||
    (first === 192 && second === 168) ||
    (first === 169 && second === 254) ||
    first === 0;
}

function debugLog(message: string, value: unknown): void {
  if (Deno.env.get("DEBUG_RECIPE_IMPORT") !== "true") {
    return;
  }

  console.log(`[import-recipe-url] ${message}:`, value);
}
