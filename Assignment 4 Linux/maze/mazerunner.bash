#!/bin/bash

# Check if jq is installed
if ! command -v jq &> /dev/null
then
    echo "jq could not be found. Please install jq before running this script."
    exit
fi

# Check if curl is installed
if ! command -v curl &> /dev/null
then
    echo "curl could not be found. Please install curl before running this script."
    exit
fi

# check if there are any arguments
if [ $# -eq 0 ]
then
    echo "No arguments supplied"
    exit 1
fi

# Initiate a game and save the game ID in a file.
init () {
  RESPONSE=$(curl -s http://localhost:1337/)
  if [ -z "$RESPONSE" ]; then
    echo "Failed to get a response from the server."
    return
  fi
  
  GAME_ID=$(echo "$RESPONSE" | jq -r '.gameid')
  if [ -z "$GAME_ID" ]; then
    echo "Failed to extract game ID from the server's response."
    return
  fi
  
  echo "${GAME_ID}" > gameID.txt
  if [ $? -ne 0 ]; then
    echo "Failed to write game ID to gameID.txt."
    return
  fi
  
  echo "Game has been initialized. The game has the following ID:"
  echo "${GAME_ID}"
}


# Show which maps are available to choose from.
maps () {
  MAPS=$(curl -s http://localhost:1337/map | jq -r '.[]')
  echo "Following maps are available:"
  I=1
  for MAP in $MAPS
  do
    echo "$I. $MAP"
    I=$((I + 1))
  done
  echo "Use ./mazerunner.bash select # to select a map"
}

# Select a specific map by number.
select_ () {
  read -r GAME_ID < gameID.txt
  MAPS=$(curl -s http://localhost:1337/map | jq -r '.[]')
  I=1
  for MAP in $MAPS
  do
    if [[ "$I" -eq "$1" ]]
    then
      break
    fi
    I=$((I + 1))
  done
  curl -s "http://localhost:1337/${GAME_ID}/map/{$MAP}" > /dev/null  # Suppress the output here
  echo "Following map has been selected:"
  echo "$MAP"
  echo "Use ./mazerunner.bash enter to start the game and play manually"
}

# Enter the first room.
enter () {
  read -r GAME_ID < gameID.txt
  ROOM=$(curl -s "http://localhost:1337/${GAME_ID}/maze/")
  echo "$ROOM" | jq -r .roomid > roomID.txt
  info
}

# Show information about the room.
info () {
  read -r GAME_ID < gameID.txt
  read -r ROOM_ID < roomID.txt
  ROOM=$(curl -s "http://localhost:1337/${GAME_ID}/maze/{$ROOM_ID}")
  echo "You are in room: ${ROOM_ID}"
  DESCRIPTION=$(echo "$ROOM" | jq -r '.description')
  if [[ -z "$DESCRIPTION" ]]
  then
    DESCRIPTION="Room ${ROOM_ID}"
  fi
  echo "Description: $DESCRIPTION"
  DIRECTIONS=$(echo "$ROOM" | jq -r '.directions')
  echo "$DIRECTIONS" > directions.txt
  EAST=$(echo "$DIRECTIONS" | jq -r '.east')
  SOUTH=$(echo "$DIRECTIONS" | jq -r '.south')
  WEST=$(echo "$DIRECTIONS" | jq -r '.west')
  NORTH=$(echo "$DIRECTIONS" | jq -r '.north')
  CAN_GO=""
  if [[ "$EAST" != "-" ]]
  then
    CAN_GO="${CAN_GO}east, "
  fi
  if [[ "$SOUTH" != "-" ]]
  then
    CAN_GO="${CAN_GO}south, "
  fi
  if [[ "$WEST" != "-" ]]
  then
    CAN_GO="${CAN_GO}west, "
  fi
  if [[ "$NORTH" != "-" ]]
  then
    CAN_GO="${CAN_GO}north, "
  fi
  echo "You can go to: ${CAN_GO}"
}

# Go to a new room, if the direction is supported.
go () {
  read -r GAME_ID < gameID.txt
  read -r ROOM_ID < roomID.txt
  ROOM=$(curl -s "http://localhost:1337/${GAME_ID}/maze/${ROOM_ID}/${1}")
  echo "$ROOM" | jq -r .roomid > roomID.txt
  info
}

# Automatically solve each map
auto() {

  # Get the list of available maps
  MAPS=$(curl -s http://localhost:1337/map | jq -r '.[]')
  MAP_COUNT=$(echo "$MAPS" | wc -l)

  # Solve each map
  for ((i=1; i<=MAP_COUNT; i++)); do
    echo "Solving map $i of $MAP_COUNT"
    
    # start map
    init
    select_ "$i"
    enter

    # create last move variable
    LAST_MOVE="east"

    # try solve in max 100 moves (to prevent cycling out) using right hand maze solving algorithm
    for I in {0..99}; do
      # get info, directions, and check if we are not done
      ROOM=$(curl -s "http://localhost:1337/${GAME_ID}/maze/${ROOM_ID}")

      # Check if "You found the exit" is in the response
      if echo "$ROOM" | grep -q "You found the exit"; then
        echo "Game finished for map $i!"
        break
      fi

      DIRECTIONS=$(echo "$ROOM" | jq -r '.directions')
      EAST=$(echo "$DIRECTIONS" | jq -r '.east')
      SOUTH=$(echo "$DIRECTIONS" | jq -r '.south')
      WEST=$(echo "$DIRECTIONS" | jq -r '.west')
      NORTH=$(echo "$DIRECTIONS" | jq -r '.north')

      # use right-hand rule algorithm to choose another move, and save it to LAST_MOVE variable
      case "$LAST_MOVE" in
        east)
          [[ "$SOUTH" != "-" ]] && { go "south"; LAST_MOVE="south"; continue; }
          [[ "$EAST" != "-" ]] && { go "east"; LAST_MOVE="east"; continue; }
          [[ "$NORTH" != "-" ]] && { go "north"; LAST_MOVE="north"; continue; }
          ;;
        south)
          [[ "$WEST" != "-" ]] && { go "west"; LAST_MOVE="west"; continue; }
          [[ "$SOUTH" != "-" ]] && { go "south"; LAST_MOVE="south"; continue; }
          [[ "$EAST" != "-" ]] && { go "east"; LAST_MOVE="east"; continue; }
          ;;
        west)
          [[ "$NORTH" != "-" ]] && { go "north"; LAST_MOVE="north"; continue; }
          [[ "$WEST" != "-" ]] && { go "west"; LAST_MOVE="west"; continue; }
          [[ "$SOUTH" != "-" ]] && { go "south"; LAST_MOVE="south"; continue; }
          ;;
        north)
          [[ "$EAST" != "-" ]] && { go "east"; LAST_MOVE="east"; continue; }
          [[ "$NORTH" != "-" ]] && { go "north"; LAST_MOVE="north"; continue; }
          [[ "$WEST" != "-" ]] && { go "west"; LAST_MOVE="west"; continue; }
          ;;
      esac

      # default move if none of the directions from the right-hand rule can be taken
      go "east"
      LAST_MOVE="east"
    done

  done
}


# main command switch
case $1 in
  init)
    init
    ;;
  maps)
    maps
    ;;
  select)
    select_ "$2"
    ;;
  enter)
    enter
    ;;
  info)
    info
    ;;
  go)
    go "$2"
    ;;
  auto)
    auto "$2"
    ;;
  *)
    echo "Bad command"
    ;;
esac


