#!/usr/bin/env bash
# set -x

# when no arguments was given
if [ $# -eq 0 ]
then
  HOST=$(minikube ip).nip.io
else
  HOST=$0
fi

# kill all CrashLoopBackOff and ImagePullBackOff pods to trigger a fast restart and not wait Kubernetes
kubectl get pods -A | grep -E "(BackOff|Error)" | tr -s " " | cut -d" " -f1-2 | xargs -r -L 1 kubectl delete pod -n

MAXRETRIES=600

declare -A SERVICES=( \
 ["keycloak.${HOST}"]="realms/master/.well-known/openid-configuration" \
 ["grafana.${HOST}"]="" \
 ["prometheus.${HOST}"]="" \
 ["jaeger.${HOST}"]="api/services" \
 ["kubebox.${HOST}"]="" \
 ["cryostat.${HOST}"]="" \
 )

for SERVICE in "${!SERVICES[@]}"; do
  RETRIES=$MAXRETRIES
  # loop until we connect successfully or failed

  if [ "${SERVICE}" == "keycloak.${HOST}" ]
  then
    until [ "$(kubectl get keycloak/keycloak -n keycloak -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')" == "true" ]
    do
      RETRIES=$(($RETRIES - 1))
      if [ $RETRIES -eq 0 ]
      then
          kubectl get keycloak/keycloak -n keycloak -o jsonpath='{.status}'
          echo
          echo "Failed waiting for keycloak operator status to become ready"
          exit 1
      fi
      # wait a bit
      if [ "$GITHUB_ACTIONS" == "" ]; then
        echo -n "."
      fi
      sleep 5
    done
  fi

  until kubectl get ingress -A 2>/dev/null | grep ${SERVICE} >/dev/null && curl -k -f -v https://${SERVICE}/${SERVICES[${SERVICE}]} >/dev/null 2>/dev/null
  do
    RETRIES=$(($RETRIES - 1))
    if [ $RETRIES -eq 0 ]
    then
        echo "Failed to connect"
        exit 1
    fi
    # wait a bit
    if [ "$GITHUB_ACTIONS" == "" ]; then
      echo -n "."
    fi
    sleep 5
  done

  if [ "${SERVICE}" == "jaeger.${HOST}" ]
  then
    until curl -k -f -v https://${SERVICE}/${SERVICES[${SERVICE}]} -o - 2>/dev/null | grep "jaeger-query" >/dev/null 2>/dev/null
    do
      RETRIES=$(($RETRIES - 1))
      if [ $RETRIES -eq 0 ]
      then
          echo "Failed to see service jaeger-query in the list of Jaeger services"
          exit 1
      fi
      # wait a bit
      if [ "$GITHUB_ACTIONS" == "" ]; then
        echo -n "."
      fi
      sleep 5
    done
  fi

  echo https://${SERVICE}/ is up
done
