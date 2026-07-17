# RecipeManager

## Overview

`RecipeManager` is a static Godot class that centralizes recipe data for food item combinations and allows runtime lookup of result scenes.

The manager loads a single YAML file at startup: `res://recipes.yaml`, using the installed `addons/yaml` addon.

## Responsibilities

- Load recipe definitions from `recipes.yaml`.
- Provide symmetric lookups for two-item combining recipes so `A + B` and `B + A` map to the same result.
- Resolve item IDs to their corresponding scene resources.
- Print all loaded combining recipes when the application starts.

## Data structure in `recipes.yaml`

The recipe YAML file contains two top-level sections:

- `items`: maps item IDs to their scene path and optional metadata.
- `combining`: maps result item IDs to one or more recipe pairs.

Example structure:

```yaml
items:
  hamburger:
    scene: res://Items/hamburger.tscn
    type: meal
  burger_buns:
    scene: res://Items/BurgerBuns.tscn
    type: ingredient

combining:
  hamburger:
    - [cooked_burger, burger_buns]
    - [charcoal, charcoal]
  charcoal:
    - [cube, cube]
```

### `items`

Each entry under `items` uses the item ID as the key.
The manager reads the `scene` field for each item and uses it to resolve the packed scene for recipe results.

### `combining`

Each entry under `combining` represents a result item ID, and its value is a list of recipe pairs.
Each recipe pair is a two-item array of ingredient IDs.
This allows a single result item to have multiple valid recipes.

The manager normalizes each ingredient pair using a sorted key string internally, so lookups are symmetric.

## Runtime behavior

- `FoodItem.id` is used when combining items to look up the recipe result.
- `RecipeManager.get_combination(first_id, second_id)` computes a canonical key for the pair and returns the resulting item's scene.
- On startup, `main.gd` calls `RecipeManager.print_all_recipes()`, which logs each combining recipe in the form:

  `ingredient_a + ingredient_b -> result_id`

## Notes

- `RecipeManager` prefers the installed YAML addon to parse `recipes.yaml` when it is available.
- If the addon is unavailable in the current runtime, the manager falls back to a lightweight built-in parser for the simple `items`/`combining` file format.
- Scene paths now live in the YAML data instead of being hardcoded in the manager.
- Because `RecipeManager` is static, it can be used from any script without creating an instance.
