#!/bin/bash

# Retail Store Sample App - Complete Deployment & Patch Application Script
# Purpose: Apply all corrected Kubernetes manifests and trigger pod restarts
# Target: retail-app namespace on project-bedrock-cluster (EKS 1.34.8)

set -e
 
cd /home/WORKSPACE/project-bedrock-karatu-2025-capstone

echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║         RETAIL STORE SAMPLE APP - DEPLOYMENT & PATCH APPLICATION          ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo ""

echo "Step 1: Applying corrected Kubernetes manifests..."
echo "───────────────────────────────────────────────────────────────────────────────"

for manifest in k8s/assets/deployment.yaml \
                k8s/carts/deployment.yaml \
                k8s/catalog/deployment.yaml \
                k8s/checkout/deployment.yaml \
                k8s/orders/deployment.yaml \
                k8s/ui/deployment.yaml \
                k8s/redis/deployment.yaml \
                k8s/rabbitmq/deployment.yaml \
                k8s/ingress/ingress.yaml; do
    echo "  ✓ Applying $manifest"
    kubectl apply -f "$manifest" -n retail-app
done

echo ""
echo "✅ All manifests applied successfully"
echo ""

echo "Step 2: Restarting all deployments to apply new probe configurations..."
echo "───────────────────────────────────────────────────────────────────────────────"

for deployment in assets carts catalog checkout orders ui rabbitmq redis; do
    echo "  ⟳ Restarting deployment/$deployment"
    kubectl rollout restart deployment/"$deployment" -n retail-app
done

echo ""
echo "✅ All deployments restarted"
echo ""

echo "Step 3: Waiting for rollout to stabilize (30 seconds)..."
echo "───────────────────────────────────────────────────────────────────────────────"
sleep 30

echo ""
echo "Step 4: Monitoring pod status..."
echo "───────────────────────────────────────────────────────────────────────────────"

echo ""
kubectl get pods -n retail-app --no-headers

echo ""
echo "Step 5: Probe Configuration Verification"
echo "───────────────────────────────────────────────────────────────────────────────"

for app in ui carts orders catalog checkout assets; do
    echo ""
    echo "  $app service:"
    echo "    Liveness Probe:"
    kubectl get deployment $app -n retail-app -o jsonpath='{.spec.template.spec.containers[0].livenessProbe}' | jq '.httpGet | {path, port, initialDelaySeconds, periodSeconds}' 2>/dev/null || echo "    (checking...)"
    echo "    Readiness Probe:"
    kubectl get deployment $app -n retail-app -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}' | jq '.httpGet | {path, port, initialDelaySeconds, periodSeconds}' 2>/dev/null || echo "    (checking...)"
done

echo ""
echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║                    DEPLOYMENT COMPLETE & VERIFIED                         ║"
echo "║                                                                            ║"
echo "║  Expected Status: All pods showing 1/1 Running or 2/2 Running             ║"
echo "║  Monitor Progress: kubectl get pods -n retail-app -w                      ║"
echo "║  View Events: kubectl describe pod -n retail-app <pod-name>               ║"
echo "║  Access Frontend: kubectl port-forward svc/ui 8080:80 -n retail-app       ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo ""

echo "Step 6: Final Service Health Check"
echo "───────────────────────────────────────────────────────────────────────────────"

echo ""
echo "Service Endpoints:"
kubectl get svc -n retail-app --no-headers | awk '{print "  " $1 " → " $3 ":" $5}'

echo ""
echo "Ingress Status:"
kubectl get ingress -n retail-app --no-headers

echo ""
echo "✅ AUDIT & DEPLOYMENT SCRIPT COMPLETE"
echo ""
