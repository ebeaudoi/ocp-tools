#!/usr/bin/env bash

#set -x
set -e -o pipefail
shopt -s extglob
########################################
########################################
# ** TO DO BEFORE TO RUN THE SCRIPT ** #

# 1 - Specify the version, ex: 4.12 or 4.13 or 4.14
OCP_VERSION=4.13

# 2 - keep "uncomment" only the catalogs where the operator belong
declare -A CATALOGS
CATALOGS["redhat"]="registry.redhat.io/redhat/redhat-operator-index:v$OCP_VERSION"
#CATALOGS["certified"]="registry.redhat.io/redhat/certified-operator-index:v$OCP_VERSION"
#CATALOGS["community"]="registry.redhat.io/redhat/community-operator-index:v$OCP_VERSION"
#CATALOGS["marketplace"]="registry.redhat.io/redhat/redhat-marketplace-index:v$OCP_VERSION"

# 3 - Specify the operators - modify this list as required
KEEP="elasticsearch-operator|eap|kiali-ossm|jws-operator|servicemeshoperator|odf-operator|opentelemetry-product|cluster-logging|advanced-cluster-management|openshift-gitops-operator|quay-operator|ansible-cloud-addons-operator|openshift-cert-manager-operator|ansible-automation-platform-operator|multicluster-engine|odf-csi-addons-operator|ocs-operator|mcg-operator|rhacs-operator|nfd|rhods-operator|rhsso-operator|local-storage-operator|devspaces|devworkspace-operator|amq-broker-rhel8|amq7-interconnect-operator|amq-online|amq-streams|compliance-operator|datagrid|gatekeeper-operator-product|odr-hub-operator|odr-cluster-operator|openshift-pipelines-operator-rh|redhat-oadp-operator"

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
  OUTPUTFILENAME="$catalog-op-v$OCP_VERSION-config.yaml"
  # Create the header of the ImageSet configuration file
  echo "kind: ImageSetConfiguration" >$OUTPUTFILENAME
  echo "apiVersion: mirror.openshift.io/v1alpha2" >>$OUTPUTFILENAME
  echo "storageConfig:" >>$OUTPUTFILENAME
  echo "  local:" >>$OUTPUTFILENAME
  echo "    path: ./metadata/$catalog-catalogs-v$OCP_VERSION" >>$OUTPUTFILENAME
  echo "mirror:" >>$OUTPUTFILENAME
  echo "  operators:" >>$OUTPUTFILENAME
  echo "  - catalog: ${CATALOGS[$catalog]}" >>$OUTPUTFILENAME
  echo "    targetCatalog: my-$catalog-catalog" >>$OUTPUTFILENAME
  echo "    packages:" >>$OUTPUTFILENAME

  for operator in $TMPDIR/configs/*;
  do
    if [[ -f $operator/catalog.json ]]
    then
      OPNAME=$(jq -cs . $operator/catalog.json |jq .[0].name)
      OPDEFCHAN=$(jq -cs . $operator/catalog.json |jq .[0].defaultChannel)
      OPRELEASE=$(jq -cs . $operator/catalog.json |jq ".[] |select(.name==$OPDEFCHAN)"|jq .entries[].name)
      LATESTRELEASE=$(echo $OPRELEASE|awk '{print $NF}')
      echo "$COUNTOPS/$NBOFOPERATORS -- Adding operator=$OPNAME with channel=$OPDEFCHAN and version $LATESTRELEASE"
      ((COUNTOPS++))
      echo "    - name: $OPNAME" >>$OUTPUTFILENAME
      echo "      channels:" >>$OUTPUTFILENAME
      echo "      - name: $OPDEFCHAN" >>$OUTPUTFILENAME
      echo "        minVersion: $LATESTRELEASE" >>$OUTPUTFILENAME
      echo "        maxVersion: $LATESTRELEASE" >>$OUTPUTFILENAME
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


