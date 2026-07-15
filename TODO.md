


- Move recipes into a Yaml file that is read, and handles symetry through a Static manager class?
	Example:
		```yaml
			combining:
				cooked_burger:
					- cooked_burger
					- burger_buns
					
			cooking:
				cooked_burger: raw_burger
				charcoal: cooked_burger
				charcoal: toast
		```
		```gd
			on_area_enter(other):
				var result = RecipeManager.getCombination(my_id, other_id)
				if result:
					convertInto(result)
		```
