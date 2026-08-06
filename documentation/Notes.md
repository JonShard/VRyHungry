## Stations
counter
hob
sink
table
extra knife
extre rolling pin
mop
bin

## Food dispensers
burger
buns
potato
tomato
onion
flour
pasta plates
meat
cheese

## Automation
belt
inserter
splitter
mixer
blender
dishwasher
flinger / catapult

## Storage
shelf
freezer
frozen prep station equivilant

## Control
Phone
Napkins (no mess consumable)
sharp cutlery (eat faster consumable)
Self order terminal




inserter
  filer
  output min empty space slider

belts share inventory

tables share 


Shared INventory
    Raycasts[]
    Area3D

    list


## Customer design
- A customer is a simple goto point object. has queue_patience float
- A customer is spawned in street, told to move to QueueController Area
- A QueueController tracks the entered customer and tells it to take a queue position 
- A QueueController displays a progress bar above door of queue_patience of the customer in the Area3D with the least patience.
- On new table available, QueueController tells front customer in queue to sit at table





## Modifiers
- Disposable plates. no washing. much less money



## Weird ideas
- carry 4 plates. A snapzone on forearm that only accept plate, and drops it if tilted too much. Real waiter feel.


## Research
- Reasearch is its own currency. 
- You unlock items in shop with reseach points. Then you can buy them. You "buy" the same tile twice.





## NEtwork TOTO
- Make gamemanager a node with syncroniser
- All stations 

- Client purchases don't spawn