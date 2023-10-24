#!/bin/bash

# Check if jq is installed
if ! command -v jq &> /dev/null
then
    echo "jq could not be found. Please install jq before running this script."
    exit
fi

# check if there are any arguments
if [ $# -eq 0 ]
then
    echo "No arguments supplied"
    exit 1
fi

# helping function for displaying horizontal line
separator () {
  echo "----------------------------------------"
}

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
  
  separator
  echo "Game has been initialized. The game has the following id:"
  echo "${GAME_ID}"
}


# Show which maps are available to choose from.
maps () {
  MAPS=$(curl -s http://localhost:1337/map | jq -r '.[]')
  separator
  echo "Following maps are available: "
  I=1
  for MAP in $MAPS
  do
    echo "$I $MAP"
    I=$((I + 1))
  done
  echo "Use ./mazerunner.bash select # to select a map"
}

# Select a specific map by number.
select_ () {
  # read game id from file
  read -r GAME_ID < gameID.txt

  # call api
  MAPS=$(curl -s http://localhost:1337/map | jq -r '.[]')

  # select map that was pick by index
  I=1

  for MAP in $MAPS
  do
    if [[ "$I" -eq "$1" ]]
    then
      break
    fi
  done

  # call api to select map
  curl -s "http://localhost:1337/${GAME_ID}/map/{$MAP}"

  # print information
  separator
  echo "Following map has been selected: ${I}. ${MAP}"
}

# Enter the first room.
enter () {
  # read game id from file
  read -r GAME_ID < gameID.txt
  # call api
  ROOM=$(curl -s "http://localhost:1337/${GAME_ID}/maze/")

  # print information
  echo "You have entered the maze."
  # save room id to file
  echo "$ROOM" | jq -r .roomid > roomID.txt
}

# Show information about the room.
info () {
  # read game id and room id
  read -r GAME_ID < gameID.txt
  read -r ROOM_ID < roomID.txt

  # call api
  ROOM=$(curl -s "http://localhost:1337/${GAME_ID}/maze/{$ROOM_ID}")

  # print info
  separator
  echo "You are in room: ${ROOM_ID}"

  # get description if any
  DESCRIPTION=$(echo "$ROOM" | jq -r '.description')

  # create default description
  if [[ -z "$DESCRIPTION" ]]
  then
    DESCRIPTION="Room ${ROOM_ID}"
  fi

  # print description
  echo "Description: $DESCRIPTION"

  # we found the exit, finish the game
  if [[ "$DESCRIPTION" == "You found the exit" ]]
  then
    echo "done" > done.txt
    return 0
  fi

  # if we didn't finish keep file empty
  echo "" > done.txt

  # parse directions
  DIRECTIONS=$(echo "$ROOM" | jq -r '.directions')
  # store them in file
  echo "$DIRECTIONS" > directions.txt

  # parse where we can go
  EAST=$(echo "$DIRECTIONS" | jq -r '.east')
  SOUTH=$(echo "$DIRECTIONS" | jq -r '.south')
  WEST=$(echo "$DIRECTIONS" | jq -r '.west')
  NORTH=$(echo "$DIRECTIONS" | jq -r '.north')

  # create variable
  CAN_GO=""

  # create text from possible directions
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

  # print info
  echo "You can go: ${CAN_GO}"
}

# Go to a new room, if the direction is supported.
go () {
  # $1 = east, west, north, south

  # read game id and room id
  read -r GAME_ID < gameID.txt
  read -r ROOM_ID < roomID.txt

  # call api and save new room id to file
  ROOM=$(curl -s "http://localhost:1337/${GAME_ID}/maze/${ROOM_ID}/${1}")
  echo "$ROOM" | jq -r .roomid > roomID.txt
}

# Automatically solve a map
auto () {
  # $1 = map number

  # automatically start map
  init
  maps
  select_ "$1"
  enter
  # create last move variable
  LAST_MOVE="east"

  # try solve in max 100 moves (to prevent cycling out) using right hand maze solving algorithm
  for I in {0..99}
  do
    # get info, directions, and check if we are not done
    info
    DIRECTIONS=$(cat directions.txt)
    read -r DONE < done.txt

    # if done break for cycle
    if [[ "$DONE" == "done" ]]
      then
        break
    fi

    # parse where we can go
    EAST=$(echo "$DIRECTIONS" | jq -r '.east')
    SOUTH=$(echo "$DIRECTIONS" | jq -r '.south')
    WEST=$(echo "$DIRECTIONS" | jq -r '.west')
    NORTH=$(echo "$DIRECTIONS" | jq -r '.north')

    # use right-hand rule algorithm to choose another move, and save it to LAST_MOVE variable
    # when we do possible move, continue for cycle
    case "$LAST_MOVE" in
      east)
        if [[ "$SOUTH" != "-" ]]
        then
          go "south"
          LAST_MOVE="south"
          continue
        fi

        if [[ "$EAST" != "-" ]]
        then
          go "east"
          LAST_MOVE="east"
          continue
        fi

        if [[ "$NORTH" != "-" ]]
        then
          go "north"
          LAST_MOVE="north"
          continue
        fi
        ;;

      south)
        if [[ "$WEST" != "-" ]]
        then
          go "west"
          LAST_MOVE="west"
          continue
        fi

        if [[ "$SOUTH" != "-" ]]
        then
          go "south"
          LAST_MOVE="south"
          continue
        fi

        if [[ "$EAST" != "-" ]]
        then
          go "east"
          LAST_MOVE="east"
          continue
        fi
        ;;

      west)
        if [[ "$NORTH" != "-" ]]
        then
          go "north"
          LAST_MOVE="north"
          continue
        fi

        if [[ "$WEST" != "-" ]]
        then
          go "west"
          LAST_MOVE="west"
          continue
        fi

        if [[ "$SOUTH" != "-" ]]
        then
          go "south"
          LAST_MOVE="south"
          continue
        fi
        ;;

      north)
        if [[ "$EAST" != "-" ]]
        then
          go "east"
          LAST_MOVE="east"
          continue
        fi

        if [[ "$NORTH" != "-" ]]
        then
          go "north"
          LAST_MOVE="north"
          continue
        fi

        if [[ "$WEST" != "-" ]]
        then
          go "west"
          LAST_MOVE="west"
          continue
        fi
        ;;
    esac

    # if we didn't go yet, we go east
    go "east"
    LAST_MOVE="east"
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
