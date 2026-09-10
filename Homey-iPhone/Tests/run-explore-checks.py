#!/usr/bin/env python3
"""Run the production paging state machine without credentials or backend mutations."""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'Homey-iPhone/Features/Meals/ExploreRecipeService.swift').read_text()
# Replace only the Supabase adapter so the actual production state machine runs with a fake provider.
start = source.index('/// Keeps ordering')
end = source.index('@MainActor\nfinal class ExploreRecipesViewModel')
source = source[:start] + source[end:]
source = source.replace('import Supabase\n', '')
source = source.replace('init(service: (any ExploreRecipeProviding)? = nil)', 'init(service: any ExploreRecipeProviding)')
source = source.replace('service ?? ExploreRecipeService()', 'service')
source += '''
enum MealType: String, Codable, Hashable { case breakfast, lunch, dinner, snack, dessert, drink }
enum RecipeLibraryFilter: Hashable { case all, favorites, breakfast, lunch, dinner, dessert }
'''
with tempfile.TemporaryDirectory(prefix='homey-explore-') as directory:
    directory = Path(directory)
    production = directory / 'Production.swift'
    production.write_text(source)
    binary = directory / 'checks'
    env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', str(directory / 'cache'), str(production), str(root / 'Tests/ExplorePaginationChecks.swift'), '-o', str(binary)], env=env, check=True)
    subprocess.run([str(binary)], check=True)
