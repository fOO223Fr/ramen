// SPDX-FileCopyrightText: The RamenDR authors
// SPDX-License-Identifier: Apache-2.0

package controllers

import (
	"context"
	"testing"
	"time"

	volrep "github.com/csi-addons/kubernetes-csi-addons/api/replication.storage/v1alpha1"
	"github.com/go-logr/logr"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	ramendrv1alpha1 "github.com/ramendr/ramen/api/v1alpha1"
	rmnutil "github.com/ramendr/ramen/internal/controller/util"
)

const (
	resyncTestVRGeneration = 2
	resyncTestVGRCName     = "vgrc-resync"
)

func resyncTestCondition(conditionType string, status metav1.ConditionStatus, generation int64) metav1.Condition {
	return metav1.Condition{
		Type:               conditionType,
		Status:             status,
		ObservedGeneration: generation,
		Reason:             "Test",
		LastTransitionTime: metav1.Now(),
	}
}

func notReplicatingConditions(generation int64) []metav1.Condition {
	return []metav1.Condition{
		resyncTestCondition(volrep.ConditionValidated, metav1.ConditionTrue, generation),
		resyncTestCondition(volrep.ConditionCompleted, metav1.ConditionTrue, generation),
		resyncTestCondition(volrep.ConditionReplicating, metav1.ConditionFalse, generation),
	}
}

func replicatingConditions() []metav1.Condition {
	return []metav1.Condition{
		resyncTestCondition(volrep.ConditionValidated, metav1.ConditionTrue, resyncTestVRGeneration),
		resyncTestCondition(volrep.ConditionCompleted, metav1.ConditionTrue, resyncTestVRGeneration),
		resyncTestCondition(volrep.ConditionReplicating, metav1.ConditionTrue, resyncTestVRGeneration),
	}
}

func resyncingConditions() []metav1.Condition {
	return []metav1.Condition{
		resyncTestCondition(volrep.ConditionCompleted, metav1.ConditionTrue, resyncTestVRGeneration),
		resyncTestCondition(volrep.ConditionDegraded, metav1.ConditionTrue, resyncTestVRGeneration),
		resyncTestCondition(volrep.ConditionResyncing, metav1.ConditionTrue, resyncTestVRGeneration),
	}
}

func resyncCompletedConditions() []metav1.Condition {
	return []metav1.Condition{
		resyncTestCondition(volrep.ConditionCompleted, metav1.ConditionTrue, resyncTestVRGeneration),
		resyncTestCondition(volrep.ConditionDegraded, metav1.ConditionFalse, resyncTestVRGeneration),
		resyncTestCondition(volrep.ConditionResyncing, metav1.ConditionFalse, resyncTestVRGeneration),
	}
}

func resyncTestVR(state volrep.ReplicationState, conditions []metav1.Condition) *volrep.VolumeReplication {
	return &volrep.VolumeReplication{
		ObjectMeta: metav1.ObjectMeta{
			Name:       "pvc-a",
			Namespace:  "vrg-ns",
			Generation: resyncTestVRGeneration,
		},
		Spec: volrep.VolumeReplicationSpec{
			ReplicationState: state,
		},
		Status: volrep.VolumeReplicationStatus{
			ObservedGeneration: resyncTestVRGeneration,
			Conditions:         conditions,
		},
	}
}

func promotedConditions() []metav1.Condition {
	return []metav1.Condition{
		resyncTestCondition(volrep.ConditionCompleted, metav1.ConditionTrue, resyncTestVRGeneration),
		resyncTestCondition(volrep.ConditionDegraded, metav1.ConditionFalse, resyncTestVRGeneration),
		resyncTestCondition(volrep.ConditionResyncing, metav1.ConditionFalse, resyncTestVRGeneration),
		resyncTestCondition(volrep.ConditionReplicating, metav1.ConditionFalse, resyncTestVRGeneration),
	}
}

// resyncTestVGR returns a VGR in the given state, whose status conditions are all stamped with the VGR generation,
// as csi-addons does when copying the status from the backing VR.
func resyncTestVGR(state volrep.ReplicationState, vrName string, conditions []metav1.Condition,
) *volrep.VolumeGroupReplication {
	vgrConditions := make([]metav1.Condition, len(conditions))
	for i := range conditions {
		vgrConditions[i] = conditions[i]
		vgrConditions[i].ObservedGeneration = resyncTestVRGeneration
	}

	return &volrep.VolumeGroupReplication{
		ObjectMeta: metav1.ObjectMeta{
			Name:       "vgr-a",
			Namespace:  "vrg-ns",
			Generation: resyncTestVRGeneration,
		},
		Spec: volrep.VolumeGroupReplicationSpec{
			ReplicationState:                state,
			VolumeReplicationName:           vrName,
			VolumeGroupReplicationClassName: resyncTestVGRCName,
		},
		Status: volrep.VolumeGroupReplicationStatus{
			VolumeReplicationStatus: volrep.VolumeReplicationStatus{
				ObservedGeneration: resyncTestVRGeneration,
				Conditions:         vgrConditions,
			},
		},
	}
}

func resyncTestVGRC(labeled bool) *volrep.VolumeGroupReplicationClass {
	vgrc := &volrep.VolumeGroupReplicationClass{
		ObjectMeta: metav1.ObjectMeta{Name: resyncTestVGRCName},
		Spec: volrep.VolumeGroupReplicationClassSpec{
			Provisioner: "test.provisioner",
		},
	}
	if labeled {
		vgrc.SetLabels(map[string]string{rmnutil.ResyncOnPrimaryLabel: "true"})
	}

	return vgrc
}

// resyncTestT is the subset of testing.T used by the resync test helpers, so that they can also be used from
// Ginkgo specs with GinkgoT().
type resyncTestT interface {
	Helper()
	Fatalf(format string, args ...any)
}

// resyncTestVRGInstanceWithObjects builds a primary async VRGInstance backed by a fake client holding the
// supplied objects.
func resyncTestVRGInstanceWithObjects(t resyncTestT, deleted bool, objs ...client.Object) *VRGInstance {
	t.Helper()

	scheme := runtime.NewScheme()
	if err := corev1.AddToScheme(scheme); err != nil {
		t.Fatalf("AddToScheme: %v", err)
	}

	if err := volrep.AddToScheme(scheme); err != nil {
		t.Fatalf("AddToScheme: %v", err)
	}

	vrg := &ramendrv1alpha1.VolumeReplicationGroup{
		ObjectMeta: metav1.ObjectMeta{Name: "vrg", Namespace: "vrg-ns", Generation: 1},
		Spec: ramendrv1alpha1.VolumeReplicationGroupSpec{
			ReplicationState: ramendrv1alpha1.Primary,
			Async:            &ramendrv1alpha1.VRGAsyncSpec{},
		},
	}

	if deleted {
		deletedAt := metav1.NewTime(time.Unix(1000, 0))
		vrg.SetDeletionTimestamp(&deletedAt)
	}

	return &VRGInstance{
		reconciler: &VolumeReplicationGroupReconciler{
			Client: fake.NewClientBuilder().WithScheme(scheme).WithObjects(objs...).Build(),
		},
		ctx:              context.TODO(),
		log:              logr.Discard(),
		instance:         vrg,
		grpReplClassList: &volrep.VolumeGroupReplicationClassList{},
	}
}

type resyncOnPrimaryVRCase struct {
	name       string
	vrState    volrep.ReplicationState
	conditions []metav1.Condition
	wantState  volrep.ReplicationState
	wantReady  bool
}

func assertResyncOnPrimaryVR(t *testing.T, tc resyncOnPrimaryVRCase) {
	t.Helper()

	v := resyncTestVRGInstanceWithObjects(t, false, resyncTestVR(tc.vrState, tc.conditions))
	pvc := livePVC("pvc-a")

	volRep := &volrep.VolumeReplication{}
	if err := v.reconciler.Get(v.ctx, types.NamespacedName{Name: "pvc-a", Namespace: "vrg-ns"}, volRep); err != nil {
		t.Fatalf("Get VR: %v", err)
	}

	_, ready, err := v.updateVR(&pvc, volRep, volrep.Primary, logr.Discard())
	if err != nil {
		t.Fatalf("updateVR() error = %v", err)
	}

	if ready != tc.wantReady {
		t.Errorf("updateVR() ready = %v, want %v", ready, tc.wantReady)
	}

	got := &volrep.VolumeReplication{}
	if err := v.reconciler.Get(v.ctx, types.NamespacedName{Name: "pvc-a", Namespace: "vrg-ns"}, got); err != nil {
		t.Fatalf("Get VR: %v", err)
	}

	if got.Spec.ReplicationState != tc.wantState {
		t.Errorf("VR replicationState = %q, want %q", got.Spec.ReplicationState, tc.wantState)
	}
}

// TestResyncOnPrimaryVR confirms the VR-only path does not enter Spec=Resync (unsupported; VGRC-only).
func TestResyncOnPrimaryVR(t *testing.T) {
	t.Parallel()

	tests := []resyncOnPrimaryVRCase{
		{
			name: "not replicating, stays primary", vrState: volrep.Primary,
			conditions: notReplicatingConditions(resyncTestVRGeneration), wantState: volrep.Primary, wantReady: true,
		},
		{
			name: "existing Resync Spec forced back to Primary (VR path unsupported)", vrState: volrep.Resync,
			conditions: resyncingConditions(), wantState: volrep.Primary,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			assertResyncOnPrimaryVR(t, tt)
		})
	}
}

type resyncOnPrimaryVGRCase struct {
	name         string
	vgrcLabeled  bool
	global       bool
	deleted      bool
	vgrState     volrep.ReplicationState
	vrName       string
	vrState      volrep.ReplicationState
	vrConditions []metav1.Condition
	wantState    volrep.ReplicationState
}

func assertResyncOnPrimaryVGR(t *testing.T, tc resyncOnPrimaryVGRCase) {
	t.Helper()

	vgr := resyncTestVGR(tc.vgrState, tc.vrName, tc.vrConditions)
	objs := []client.Object{vgr, resyncTestVR(tc.vrState, tc.vrConditions), resyncTestVGRC(tc.vgrcLabeled)}
	v := resyncTestVRGInstanceWithObjects(t, tc.deleted, objs...)

	if tc.global {
		v.instance.SetLabels(map[string]string{GlobalVGRLabel: "global-id"})
	}

	pvc := livePVC("pvc-a")
	key := types.NamespacedName{Name: "vgr-a", Namespace: "vrg-ns"}

	volGroupRep := &volrep.VolumeGroupReplication{}
	if err := v.reconciler.Get(v.ctx, key, volGroupRep); err != nil {
		t.Fatalf("Get VGR: %v", err)
	}

	if _, _, err := v.updateVGR([]*corev1.PersistentVolumeClaim{&pvc}, volGroupRep, volrep.Primary,
		logr.Discard()); err != nil {
		t.Fatalf("updateVGR() error = %v", err)
	}

	got := &volrep.VolumeGroupReplication{}
	if err := v.reconciler.Get(v.ctx, key, got); err != nil {
		t.Fatalf("Get VGR: %v", err)
	}

	if got.Spec.ReplicationState != tc.wantState {
		t.Errorf("VGR replicationState = %q, want %q", got.Spec.ReplicationState, tc.wantState)
	}
}

func TestResyncOnPrimaryVGR(t *testing.T) {
	t.Parallel()

	tests := []resyncOnPrimaryVGRCase{
		{
			name: "no VGRC label, not replicating, stays primary", vgrState: volrep.Primary, vrName: "pvc-a",
			vrState: volrep.Primary, vrConditions: promotedConditions(), wantState: volrep.Primary,
		},
		{
			name: "VGRC labeled, not replicating, moves to resync", vgrcLabeled: true, vgrState: volrep.Primary,
			vrName: "pvc-a", vrState: volrep.Primary, vrConditions: promotedConditions(), wantState: volrep.Resync,
		},
		{
			name: "VGRC labeled, replicating, stays primary", vgrcLabeled: true, vgrState: volrep.Primary,
			vrName: "pvc-a", vrState: volrep.Primary, vrConditions: replicatingConditions(), wantState: volrep.Primary,
		},
		{
			name: "VGRC labeled, global VGR, not replicating, stays primary", vgrcLabeled: true, global: true,
			vgrState: volrep.Primary, vrName: "pvc-a", vrState: volrep.Primary, vrConditions: promotedConditions(),
			wantState: volrep.Primary,
		},
		{
			name: "VGRC labeled, backing VR not yet known, stays primary", vgrcLabeled: true, vgrState: volrep.Primary,
			vrState: volrep.Primary, vrConditions: promotedConditions(), wantState: volrep.Primary,
		},
		{
			name: "VGRC labeled, resync not yet propagated to backing VR, stays resync", vgrcLabeled: true,
			vgrState: volrep.Resync, vrName: "pvc-a", vrState: volrep.Primary, vrConditions: promotedConditions(),
			wantState: volrep.Resync,
		},
		{
			name: "VGRC labeled, resync in progress, stays resync", vgrcLabeled: true, vgrState: volrep.Resync,
			vrName: "pvc-a", vrState: volrep.Resync, vrConditions: resyncingConditions(), wantState: volrep.Resync,
		},
		{
			name: "VGRC labeled, resync completed, returns to primary", vgrcLabeled: true, vgrState: volrep.Resync,
			vrName: "pvc-a", vrState: volrep.Resync, vrConditions: resyncCompletedConditions(),
			wantState: volrep.Primary,
		},
		{
			name: "VGRC label removed, resync in progress, returns to primary", vgrState: volrep.Resync,
			vrName: "pvc-a", vrState: volrep.Resync, vrConditions: resyncingConditions(), wantState: volrep.Primary,
		},
		{
			name: "VGRC labeled, VRG deleted, resync in progress, returns to primary", vgrcLabeled: true, deleted: true,
			vgrState: volrep.Resync, vrName: "pvc-a", vrState: volrep.Resync, vrConditions: resyncingConditions(),
			wantState: volrep.Primary,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			assertResyncOnPrimaryVGR(t, tt)
		})
	}
}
