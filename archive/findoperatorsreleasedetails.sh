#!/usr/bin/env bash

#set -x
#Output file - One line per operator information
ONELINEOUTPUT=false

# Verify if the operator catalog release has been provided
if [[ $# == 1 ]]; then
    OCP_VERSION=$1
elif [[ $# == 2 ]]; then
    OCP_VERSION=$1
else
    echo "Usage: $0 <ocp_version>.  ex: 4.13 or 4.14"
    exit 1
fi

#Create the catalogs with all sources
declare -A CATALOGS
#CATALOGS["redhat"]="registry.redhat.io/redhat/redhat-operator-index:v$OCP_VERSION"
#CATALOGS["certified"]="registry.redhat.io/redhat/certified-operator-index:v$OCP_VERSION"
#CATALOGS["community"]="registry.redhat.io/redhat/community-operator-index:v$OCP_VERSION"
#CATALOGS["marketplace"]="registry.redhat.io/redhat/redhat-marketplace-index:v$OCP_VERSION"

#Ask which catalog should be used or ALL
echo "--------------------"
echo "which catalog(s)?"
echo "1 - Red Hat Operators"
echo "2 - Certified Operators"
echo "3 - Community Operators"
echo "4 - Marketplace Operators"
echo "5 - All"
while IFS= read -s -r -n 1 choice; do 
  case $choice in
    1) CATALOGS["redhat"]="registry.redhat.io/redhat/redhat-operator-index:v$OCP_VERSION" 
       echo "Using Red Hat Operators catalog"
       break
       ;;
    2) CATALOGS["certified"]="registry.redhat.io/redhat/certified-operator-index:v$OCP_VERSION"
       echo "Using certified Operators catalog"
       break
       ;;
    3) CATALOGS["community"]="registry.redhat.io/redhat/community-operator-index:v$OCP_VERSION"
       echo "Using community Operators catalog"
       break
       ;;
    4) CATALOGS["marketplace"]="registry.redhat.io/redhat/redhat-marketplace-index:v$OCP_VERSION"
       echo "Using marketplace Operators catalog"
       break
       ;;
    5)
       echo "Using ALL Operators catalog"
       CATALOGS["redhat"]="registry.redhat.io/redhat/redhat-operator-index:v$OCP_VERSION"
       CATALOGS["certified"]="registry.redhat.io/redhat/certified-operator-index:v$OCP_VERSION"
       CATALOGS["community"]="registry.redhat.io/redhat/community-operator-index:v$OCP_VERSION"
       CATALOGS["marketplace"]="registry.redhat.io/redhat/redhat-marketplace-index:v$OCP_VERSION"
       break
       ;;
    *) echo "What?";;
  esac
done

# Extract the FBC data locally
for catalog in ${!CATALOGS[@]} 
do
  #Step 1 - Copy the catalog configuration file from the operator catalog container
  echo ""
  echo "-----------------------------------------------------------------------"
  echo "Copy the catalog's configuration file from the operator's catalog container"
  echo "Working with the catalog: $catalog"
  echo ""
  TMPDIR=$(mktemp -d)
  echo "Create a temporary directory: $TMPDIR"
  echo ""
  ID=$(podman run -d ${CATALOGS[$catalog]})
  echo "Run the catalog container, id: $ID"
  echo ""
  echo "Copy the catalog information to the temporary folder $TMPDIR"
  echo ""
  podman cp $ID:/configs $TMPDIR/configs
  echo "Destroy the container - $ID"
  echo ""

  #Step 2 - Get the release/channel information for each operator 
  OUTFILENAMEONELINE="$catalog-operator-channel-release-oneline.txt"
  OUTFILENAME="$catalog-operator-channel-release.txt"
  if [ $ONELINEOUTPUT == "true" ]
  then
    echo -e "OPERATOR\t\t\ttDEFAULT CHANNEL\t\t\tRELEASE"|tee -a $OUTFILENAMEONELINE
  fi
  for operator in $TMPDIR/configs/*;
  do
    if [[ -f $operator/catalog.json ]]
    then
      OUTLINE="" 
      if [ -d $operator ]; 
      then 
        OPNAME=$(jq -cs . $operator/catalog.json |jq .[0].name)
        OPDEFCHAN=$(jq -cs . $operator/catalog.json |jq .[0].defaultChannel)
        OPRELEASE=$(jq -cs . $operator/catalog.json |jq ".[] |select(.name==$OPDEFCHAN)"|jq .entries[].name)
        VERSION=""
        for release in ${OPRELEASE[@]}
        do
          export release=$(echo $release|tr -d "\"")
          VERSION="$VERSION $(jq -cs . $operator/catalog.json |jq -r --arg n "$release" '.[]|select(.name == $n)'|jq '.properties[] |select(.type=="olm.package")'|jq .value.version)"
        done
        SRTDVERSION=$(for num in $VERSION; do echo "$num"; done|sort -V)      
        if [ $ONELINEOUTPUT == "true" ]
        then
          echo ""
          OUTLINE="$OPNAME\t\t\t$OPDEFCHAN\t\t\t$OPRELEASE\t\t\t"
          for release in $(echo $OPRELEASE);do OUTLINE+="$release " ;done
          echo -e $OUTLINE |tee -a $OUTFILENAMEONELINE
        else 
          echo ""
          echo "********************************************************" |tee -a $OUTFILENAME
          echo "Operator: $OPNAME" |tee -a $OUTFILENAME
          echo "Default Channel: $OPDEFCHAN" |tee -a $OUTFILENAME
          echo "Releases:" |tee -a $OUTFILENAME
          for srtrelease in $(echo $SRTDVERSION);do echo $srtrelease |tee -a $OUTFILENAME;done
        fi
      fi
    else
      echo "catalog.json IS MISSING"
    fi
  done

  #Destory the operator catalog container
  podman rm -f $ID
  # Cleanup the tmpdir
  echo " Cleanup the tmpdir"
  rm -r $TMPDIR
  #Re-initialize the variable
  ID=""
  TMPDIR=""

done


