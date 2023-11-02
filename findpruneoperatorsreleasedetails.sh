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

#Output file - One line per operator information
ONELINEOUTPUT=false

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

  #Step 3 - Get the release/channel information for each operator 
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
          for release in $(echo $OPRELEASE);do echo $release |tee -a $OUTFILENAME;done
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


