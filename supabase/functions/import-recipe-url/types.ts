export interface RecipeImportRequest {
  home_id: string;
  url: string;
}

export interface RecipeImportResponse {
  importId: string;
  globalRecipeId: string | null;
  alreadyExists: boolean;
  normalizedUrl: string;
  recipe: ImportedRecipePreview;
}

export interface ImportedRecipePreview {
  title: string;
  description: string | null;
  imageUrl: string | null;
  prepTimeMinutes: number | null;
  cookTimeMinutes: number | null;
  totalTimeMinutes: number | null;
  servings: string | null;
  cuisine: string | null;
  mealTypes: string[];
  keywords: string[];
  ingredients: ImportedRecipeIngredient[];
  steps: ImportedRecipeStep[];
  nutrition: RecipeImportJSONValue | null;
  source: ImportedRecipeSource;
}

export interface ImportedRecipeIngredient {
  sectionName: string | null;
  ingredientName: string;
  quantity: string | null;
  isOptional: boolean;
  sortOrder: number;
}

export interface ImportedRecipeStep {
  sectionName: string | null;
  stepText: string;
  sortOrder: number;
}

export interface ImportedRecipeSource {
  originalUrl: string;
  normalizedUrl: string;
  domain: string;
  name: string | null;
}

export interface RecipeImportErrorResponse {
  error: RecipeImportAPIError;
}

export interface RecipeImportAPIError {
  code: RecipeImportAPIErrorCode;
  message: string;
}

export type RecipeImportAPIErrorCode =
  | "INVALID_URL"
  | "AUTH_REQUIRED"
  | "HOME_ACCESS_DENIED"
  | "FETCH_FAILED"
  | "NOT_HTML"
  | "NO_RECIPE_FOUND"
  | "INVALID_RECIPE_DATA"
  | "PAGE_TOO_LARGE"
  | "SOURCE_BLOCKED"
  | "SOURCE_ACCESS_DENIED"
  | "SOURCE_UNSUPPORTED"
  | "SOURCE_PARSE_FAILED"
  | "ROBOTS_DISALLOWED"
  | "TIMEOUT"
  | "INTERNAL_ERROR";

export type RecipeImportJSONValue =
  | string
  | number
  | boolean
  | RecipeImportJSONValue[]
  | { [key: string]: RecipeImportJSONValue };
