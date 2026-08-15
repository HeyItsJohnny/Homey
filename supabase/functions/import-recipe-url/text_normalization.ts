import { decode } from "https://esm.sh/html-entities@2.5.2";

export function cleanText(value: string): string {
  return normalizeWhitespace(decodeHtmlEntities(stripHtmlTags(String(value)))).trim();
}

export function decodeHtmlEntities(value: string): string {
  return decode(String(value), { level: "html5" });
}

export function normalizeWhitespace(value: string): string {
  return String(value)
    .replace(/\u00A0/g, " ")
    .replace(/[ \t\f\v]+/g, " ")
    .replace(/\s*\n\s*/g, "\n")
    .replace(/[^\S\n]+/g, " ");
}

export function stripHtmlTags(value: string): string {
  return String(value).replace(/<[^>]*>/g, " ");
}
