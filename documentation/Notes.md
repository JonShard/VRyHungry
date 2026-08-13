### Station inheritence suggestion
Station
  WorkStation (performs work on a food item to convert it)
    Hob
    Sink
    Counter
  StorageStation (one snap zone and list of positions, FILO item dispenser, like a gun magazine)
    Shelf
    PlateRak
    Dishwasher
  SharedInventoryStation (one snap zone, shares a list of connected stations with which items exist in each of them)
    Table
    Belt
  Dispenser


### Multiplayer bugs
- despan flicker for clien broken
- client keep autorityu of thrown object until lands
- in build mode, snap zones off, stations disabled
- players can steal from each others hands
- pickables being picked up is not RELIABLY synced
- sounds played on pickable in new script / node, when collides or picked_up or dropped, server tells  clinetns with RPC to play sound

- Contaioner / plate sometimes doesn't sync to clients that it picked someting up. Only when client moves a plate near a hamburger that is in a station,

- Update stations to have enable function thaat _tate_stations in network manager calls instead of disableing processing


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
- All stations need syncronizers
- Pickable not synced cooked burger on hob example
- Client purchases don't spawn items from shop. RPC adventure
- Client can not move stations including hobs, on_move handle drop is called, network pickable authority is given. but station not moved