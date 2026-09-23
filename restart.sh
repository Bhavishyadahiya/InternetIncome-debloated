#!/bin/sh

if [ "$1" = "--restartURnetwork" ]; then
  # Restarting URnetwork Nodes
  for container in $(grep '^urnetwork' containernames.txt)
  do
    docker restart $container
  done

elif [ "$1" = "--restartProxylite" ]; then
  # Restarting Proxylite Nodes
  for container in $(grep '^proxylite' containernames.txt)
  do
    docker restart $container
  done
fi
