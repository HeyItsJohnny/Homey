import { RecipeImportError } from "./errors.ts";
import { normalizeRecipeUrl } from "./url_normalization.ts";

const maxPageBytes = 2_500_000;
const timeoutMs = 12_000;
const browserUserAgent = [
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
  "AppleWebKit/537.36 (KHTML, like Gecko)",
  "Chrome/124.0 Safari/537.36",
].join(" ");

export async function fetchRecipePage(url: string): Promise<string> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  const requestDomain = hostnameOrNull(url);

  debugLog("External fetch started", {
    domain: requestDomain,
    normalizedUrl: url,
    sourcePolicy: "allowed_public_hostname",
    robotsPolicy: "not_checked",
    importerStrategy: "generic_json_ld",
  });

  let response: Response;
  try {
    response = await fetch(url, {
      signal: controller.signal,
      redirect: "follow",
      headers: {
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.9",
        "Cache-Control": "no-cache",
        "Pragma": "no-cache",
        "User-Agent": browserUserAgent,
      },
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      throw new RecipeImportError("TIMEOUT", "This recipe page took too long to respond.", 408);
    }
    throw new RecipeImportError("FETCH_FAILED", "We couldn't download this recipe page.", 502);
  } finally {
    clearTimeout(timeout);
  }

  validateFinalUrl(url, response.url);
  logExternalFetchResponse(url, response);

  if (!response.ok) {
    logExternalFetchFailure(url, response);

    if (response.status === 401 || response.status === 403) {
      debugLog("Recipe import mapped error", {
        domain: requestDomain,
        upstreamStatus: response.status,
        mappedCode: "SOURCE_ACCESS_DENIED",
      });
      throw new RecipeImportError("SOURCE_ACCESS_DENIED", "This website blocked Homey's recipe importer.", 403);
    }
    if (response.status === 404) {
      throw new RecipeImportError("FETCH_FAILED", "We couldn't find this recipe page.", 404);
    }
    if (response.status === 429) {
      debugLog("Recipe import mapped error", {
        domain: requestDomain,
        upstreamStatus: response.status,
        mappedCode: "SOURCE_ACCESS_DENIED",
      });
      throw new RecipeImportError("SOURCE_ACCESS_DENIED", "This website is temporarily limiting Homey's recipe importer.", 429);
    }
    if (response.status >= 500 && response.status <= 599) {
      throw new RecipeImportError("FETCH_FAILED", "This recipe page is temporarily unavailable.", 502);
    }
    throw new RecipeImportError("FETCH_FAILED", "We couldn't download this recipe page.", 502);
  }

  const contentType = response.headers.get("content-type")?.toLowerCase() ?? "";
  if (contentType && !contentType.includes("text/html") && !contentType.includes("application/xhtml+xml")) {
    throw new RecipeImportError("NOT_HTML", "This URL does not point to a recipe webpage.", 415);
  }

  const body = await readLimitedText(response);
  if (!looksLikeHTML(body)) {
    throw new RecipeImportError("NOT_HTML", "This URL does not point to a recipe webpage.", 415);
  }

  debugLog("Recipe import fetched HTML bytes", new TextEncoder().encode(body).byteLength);
  return body;
}

async function readLimitedText(response: Response): Promise<string> {
  if (!response.body) {
    return await response.text();
  }

  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let totalBytes = 0;

  while (true) {
    const { value, done } = await reader.read();
    if (done) {
      break;
    }

    if (!value) {
      continue;
    }

    totalBytes += value.byteLength;
    if (totalBytes > maxPageBytes) {
      try {
        await reader.cancel();
      } catch {
        // Nothing useful to do; the caller gets the typed size error.
      }
      throw new RecipeImportError("PAGE_TOO_LARGE", "This recipe page is too large to import.", 413);
    }

    chunks.push(value);
  }

  const merged = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    merged.set(chunk, offset);
    offset += chunk.byteLength;
  }

  return new TextDecoder().decode(merged);
}

function looksLikeHTML(text: string): boolean {
  const sample = text.slice(0, 2048).toLowerCase();
  return sample.includes("<!doctype html") || sample.includes("<html") || sample.includes("<script");
}

function validateFinalUrl(originalUrl: string, finalUrl: string): void {
  const finalUrlToValidate = finalUrl || originalUrl;
  try {
    normalizeRecipeUrl(finalUrlToValidate);
  } catch (error) {
    debugLog("External fetch final URL blocked", {
      domain: hostnameOrNull(originalUrl),
      finalDomain: hostnameOrNull(finalUrlToValidate),
    });
    throw error;
  }
}

function logExternalFetchFailure(originalUrl: string, response: Response): void {
  debugLog("External fetch failed", {
    domain: hostnameOrNull(originalUrl),
    status: response.status,
    finalDomain: hostnameOrNull(response.url),
    finalUrlChanged: Boolean(response.url && response.url !== originalUrl),
    contentType: response.headers.get("content-type"),
    responseSize: response.headers.get("content-length"),
  });
}

function logExternalFetchResponse(originalUrl: string, response: Response): void {
  debugLog("External fetch response", {
    domain: hostnameOrNull(originalUrl),
    finalDomain: hostnameOrNull(response.url),
    upstreamStatus: response.status,
    upstreamContentType: response.headers.get("content-type"),
    finalUrlChanged: Boolean(response.url && response.url !== originalUrl),
    importerStrategy: "generic_json_ld",
  });
}

function hostnameOrNull(url: string): string | null {
  try {
    return new URL(url).hostname.toLowerCase();
  } catch {
    return null;
  }
}

function debugLog(message: string, value: unknown): void {
  if (Deno.env.get("DEBUG_RECIPE_IMPORT") !== "true") {
    return;
  }

  console.log(`[import-recipe-url] ${message}:`, value);
}
