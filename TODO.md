


- Move recipes into a Yaml file that is read, and handles symetry through a Static manager class?
	A `FoodItem` has an ID.  
	Example:
		```yaml
			combining: # The combinging of two items, entries always have a list of exactly two items
				cooked_burger:
					- cooked_burger
					- burger_buns
				dough:
					- flour
					- water

			cooking:
				cooked_burger: 
					ingredient: raw_burger
					time: 3
				charcoal: 
					ingredient: cooked_burger
					time: 4
				charcoal: 
					ingredient: toast
					time: 2

			augmenting: # Process of adding an item onto another without changing it's type, but toggling attributes.
				cooked_burger:
					has_tomato: sliced_tomato
					has_cheese: cheese
				salad:
					has_tomato: sliced_tomato
					has_olives: olives

			chopping:
				salad: 
					ingredient: lettuce
					work: 50 # Wave arms faster makes work go faster

			rolling:
				pie_base:
					ingredient: dough
					work: 80
		```
		```py
			on_area_enter(other):
				var result = RecipeManager.getCombination(my_id, other_id)
				if result:
					convertInto(result)
		```

- Counters are stations like hobs that convert items by chopping, rolling ect depending on `RecipeManager`,   
	and only converts items after hand gestures are done enough?  

- Plates are lists of `FoodItems`? 
	Plate[`Hamburger`] accepts `Chips`           => Plate[`Hamburger`, `Chips`]
	Plate[`Hamburger`, `Chips`] accepts `Cheese` => Plate[`Hamburger(Cheese=true)`, `Chips`]
	The logic for combining has to be expanded for plates.
- Plates have a property `is_dirty` they get after a customer clears the plate, and is disabled after being processed in `Sink`
