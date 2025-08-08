#!/usr/bin/env bash
#VERSION 20250808-10h52
#set -x
set -e -o pipefail
shopt -s extglob
########################################
########################################
# ** TO DO BEFORE TO RUN THE SCRIPT ** #

# 1 - oc-mirror version (v1 or v2)
OCMIRRORVER=v2

# 2 - Specify the version, ex: 4.12 or 4.13 or 4.14
OCP_VERSION=4.18

# 3 - keep "uncomment" only the catalogs where the operator belong
declare -A CATALOGS
CATALOGS["redhat"]="registry.redhat.io/redhat/redhat-operator-index:v$OCP_VERSION"
#CATALOGS["certified"]="registry.redhat.io/redhat/certified-operator-index:v$OCP_VERSION"
#CATALOGS["community"]="registry.redhat.io/redhat/community-operator-index:v$OCP_VERSION"
#CATALOGS["marketplace"]="registry.redhat.io/redhat/redhat-marketplace-index:v$OCP_VERSION"

# 4 - Specify the operators - modify this list as required

KEEP="advanced-cluster-management"
#KEEP="elasticsearch-operator|kiali-ossm|servicemeshoperator|openshift-pipelines-operator-rh|serverless-operator|jaeger-product|rhods-operator"
	
########################################
########################################

###############################################################
#Stage 1 - Extract and prune the operators from the catalogs ##
echo "***************************************************************************"
echo "Stage 1/2 - Extract and prune the operators from the catalogs"
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
  # Pull the catalog image to make sure you have the latest
  podman pull ${CATALOGS[$catalog]}
  ID=$(podman run -d ${CATALOGS[$catalog]})
  echo "Run the catalog container, id: $ID"
  echo ""
  echo "Copy the catalog information to the temporary folder $TMPDIR"
  echo ""
  podman cp $ID:/configs $TMPDIR/configs
  echo "Destroy the container - $ID"
  echo ""

  #Step 2 - Prune the catalog
  echo ""
  echo "Prune the catalog to keep only the desired operators"
  (cd $TMPDIR/configs && rm -fr !($KEEP))
  echo ""

  ######################################################
  #Stage 2 - Generate the ImageSet configuration file ##
  echo "***************************************************************************"
  echo "Stage 2/2 - Generate the ImageSetConfiguration with all the Opertaors/version"
  COUNTOPS=1;
  NBOFOPERATORS=$(echo $KEEP|awk -F\| '{print NF}')
  OUTPUTFILENAME="$catalog-op-v$OCP_VERSION-config-$OCMIRRORVER-$(date +%Y%m%d-%HH%M).yaml"
  # Create the header of the ImageSet configuration file
  echo "kind: ImageSetConfiguration" >$OUTPUTFILENAME
  if [ $OCMIRRORVER == v1 ]
  then
    echo "apiVersion: mirror.openshift.io/v1alpha2" >>$OUTPUTFILENAME
    echo "storageConfig:" >>$OUTPUTFILENAME
    echo "  local:" >>$OUTPUTFILENAME
    echo "    path: ./metadata/$catalog-catalog-v$OCP_VERSION" >>$OUTPUTFILENAME
  else
    # oc-mirror version 2
    # v1alpha2 -> v2alpha1
    # Uses a cache system instead of metadata
    echo "apiVersion: mirror.openshift.io/v2alpha1" >>$OUTPUTFILENAME
  fi
  echo "mirror:" >>$OUTPUTFILENAME
  echo "  operators:" >>$OUTPUTFILENAME
  echo "  - catalog: ${CATALOGS[$catalog]}" >>$OUTPUTFILENAME
  echo "    targetCatalog: my-$catalog-catalog-v$(echo $OCP_VERSION| tr -d '.')" >>$OUTPUTFILENAME
  echo "    packages:" >>$OUTPUTFILENAME

  for operator in $TMPDIR/configs/*;
  do
    #Depending of the operator's author, the FBC(File-based Catalogs) can be divided in multiple files
    JSONFILEPATH=""
    if [[ -f $operator/catalog.json ]]
    then
      JSONFILEPATH="$operator/catalog.json"
    elif [[ -f $operator/index.json ]]
    then
      JSONFILEPATH="$operator/index.json"
    elif [[ -f $operator/package.json && -f $operator/channels.json && -f $operator/bundles.json ]]
    then
      cat $operator/package.json $operator/channels.json $operator/bundles.json > $operator/concatcatalog.json
      JSONFILEPATH="$operator/concatcatalog.json"
    else
      echo "NO catlog.json and NO index.json for operator $operator"
      #ebdn
      exit 1
    fi
    OPNAME=$(jq -cs . $JSONFILEPATH |jq .[0].name)
    OPDEFCHAN=$(jq -cs . $JSONFILEPATH |jq .[0].defaultChannel)
    OPRELEASE=$(jq -cs . $JSONFILEPATH |jq ".[] |select(.name==$OPDEFCHAN)"|jq .entries[].name)
    VERSION=""
    for release in ${OPRELEASE[@]}
    do
      export release=$(echo $release|tr -d "\"")
      VERSION="$VERSION $(jq -cs . $JSONFILEPATH |jq -r --arg n "$release" '.[]|select(.name == $n)'|jq '.properties[] |select(.type=="olm.package")'|jq .value.version)"
    done
    SRTDVERSION=$(for num in $VERSION; do echo "$num"; done|sort -V)
    LATESTRELEASE=$(echo $SRTDVERSION|awk '{print $NF}')
    echo "$COUNTOPS/$NBOFOPERATORS -- Adding operator=$OPNAME with channel=$OPDEFCHAN and version $LATESTRELEASE"
    ((COUNTOPS++))
    echo "    - name: $OPNAME" >>$OUTPUTFILENAME
    echo "      channels:" >>$OUTPUTFILENAME
    echo "      - name: $OPDEFCHAN" >>$OUTPUTFILENAME
    echo "        minVersion: $LATESTRELEASE" >>$OUTPUTFILENAME
#      echo "        maxVersion: $LATESTRELEASE" >>$OUTPUTFILENAME
  done

  #Destory the operator catalog container
  podman rm --time 20 -f $ID
  # Cleanup the tmpdir
  echo " Cleanup the tmpdir"
  rm -r $TMPDIR
  #Re-initialize the variable
  ID=""
  TMPDIR=""

done


