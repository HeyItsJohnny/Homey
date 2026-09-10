#!/usr/bin/env python3
"""Compile production payloads with read-only iPad contract fixtures; no backend calls."""
from pathlib import Path
import os
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
service = (root / 'Homey-iPhone/Features/Meals/MealsService.swift').read_text()
models = (root / 'Homey-iPhone/Features/Meals/MealsModels.swift').read_text()
diagnostics = (root / 'Homey-iPhone/Features/Meals/RecipeSaveDiagnostics.swift').read_text()
reference = (root.parent / 'Homey-iPad/Homey/Features/Meals/Models/MealEditorModels.swift').read_text()
source = models + '\n' + service[service.index('struct SaveMealParams:'):]
source += '\n' + next(line for line in service.splitlines() if line.startswith('enum MealsError:'))
source += '\n' + diagnostics[diagnostics.index('enum RecipeQuantity'):]
source += '\n' + reference[reference.index('struct SaveMealRecipeParameters:'):reference.index('enum MealEditorValidationField:')]
with tempfile.TemporaryDirectory(prefix='homey-save-contract-') as directory:
    directory = Path(directory)
    production = directory / 'Production.swift'
    production.write_text(source)
    binary = directory / 'checks'
    env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', str(directory / 'cache'), str(production), str(root / 'Tests/RecipeSaveContractChecks.swift'), '-o', str(binary)], env=env, check=True)
    subprocess.run([str(binary)], check=True)
