# Long-Term SFU Implementation Plan

## Executive Summary

This document outlines the roadmap for migrating from the current **Mesh-Based Video Call Architecture** (Option 3) to a **Selective Forwarding Unit (SFU)** architecture to support large-scale group video calls (10+ participants).

**Current State**: Mesh-based P2P, max 8 participants
**Target State**: SFU-based, 50+ participants per call
**Timeline**: 6-9 months
**Effort**: 200-300 engineering days

---

## Problem Statement

### Current Limitations (Mesh Architecture)

```
Bandwidth Usage (Upload per User)
─────────────────────────────────
N=2:  ~1x (direct P2P)
N=4:  ~4x (mesh with 4 peers)
N=6:  ~6x (mesh with 6 peers)
N=10: ~10x (impractical for mobile)
N=20: ~20x (impossible)

CPU Usage (Encoding/Decoding)
────────────────────────────
N=4:  1 video encode + 3 video decodes = 4 streams
N=10: 1 video encode + 9 video decodes = 10 streams (severe CPU load)
N=20: 1 video encode + 19 video decodes = 20 streams (device cannot handle)
```

### Business Requirements

1. **Scale**: Support 50+ participants per call
2. **Quality**: Maintain HD quality on mobile networks
3. **Battery**: < 15% battery drain per hour
4. **Latency**: < 200ms end-to-end latency
5. **Cost**: < $0.05 per participant-hour

---

## SFU Architecture Overview

```
┌──────────────────────────────────────────────────────────┐
│                    SFU Server (Media Server)              │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐          │
│  │ Receiver 1 │  │ Receiver 2 │  │ Receiver N │          │
│  └─────┬──────┘  └─────┬──────┘  └─────┬──────┘          │
│        │               │               │                  │
│        ├───────────────┼───────────────┤                  │
│        ▼               ▼               ▼                  │
│   ┌─────────────────────────────┐                        │
│   │  Video Mixer / Transcoder   │                        │
│   └─────────────────────────────┘                        │
│        │               │               │                  │
│        ├───────────────┼───────────────┤                  │
│        ▼               ▼               ▼                  │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐          │
│  │ Sender 1   │  │ Sender 2   │  │ Sender N   │          │
│  └────────────┘  └────────────┘  └────────────┘          │
└──────────────────────────────────────────────────────────┘
        ▲                   ▲                   ▲
        │                   │                   │
    ┌───┴─────┐         ┌───┴─────┐        ┌───┴─────┐
    │Client 1 │         │Client 2 │        │Client N │
    │(Mobile) │         │(Desktop)│        │(Tablet) │
    └─────────┘         └─────────┘        └─────────┘

Bandwidth Reduction
──────────────────
Mesh:  Each user sends N-1 streams = O(N²) total
SFU:   Each user sends 1 stream, server forwards N-1 streams = O(N) total

For N=20:
├── Mesh:  19 streams × 20 users = 380 streams (impossible)
└── SFU:   1 stream × 20 users = 20 streams + server forwarding
```

---

## Phase 1: Foundation (Months 1-2)

### Goals
- Set up SFU server infrastructure
- Implement basic media forwarding
- Upgrade signaling protocol

### Work Items

#### 1.1 Infrastructure Setup
- **Task**: Deploy SFU server (Janus, Kurento, or custom)
- **Recommendation**: Use **Janus WebRTC Server**
  - Lightweight, modular architecture
  - Built-in SFU plugin
  - Good community support
  - Can run on low-spec servers

**Estimated Effort**: 20 days

**Key Decisions**:
```
SFU Option Comparison
─────────────────────

Janus WebRTC
├── Pros: Modular, good docs, <100MB footprint
├── Cons: Learning curve, limited scaling plugins
└── Cost: Free (OSS)

Kurento
├── Pros: Rich API, flexible architecture
├── Cons: Higher resource usage, steeper learning curve
└── Cost: Free (OSS)

Millicast / Ecosystem
├── Pros: Managed service, highest reliability
├── Cons: $0.05-0.20 per participant-hour
└── Cost: Pay-as-you-go

Recommendation: Janus for MVP, migrate to managed SFU later
```

**Setup Steps**:
```bash
# Install Janus on dedicated VM
./install_janus.sh

# Configure SFU plugin
configure_sfu_plugin.yaml

# Test with RTSP/RTMP streams
test_media_forwarding.sh
```

#### 1.2 Signaling Protocol Upgrade
- **Current**: Simple SDP exchange for mesh
- **New**: Full SFU signaling with ICE candidates

**Protocol Changes**:

```json
// Current Mesh Signaling
{
  "type": "join",
  "sdp": "v=0\r\n...",
  "participants": [...]
}

// New SFU Signaling
{
  "type": "join",
  "sdp": "v=0\r\n...",
  "sfu_url": "wss://sfu.example.com:8449",
  "sfu_session_id": "uuid",
  "ice_candidates": [...]
}
```

**Implementation**:
- Update `/api/v1/calls/{id}/join` endpoint
- Add SFU URL and session ID to response
- Implement ICE candidate trickling

**Estimated Effort**: 15 days

### Deliverables
- ✅ Janus SFU deployed and tested
- ✅ Signaling protocol v2 implemented
- ✅ 4-user test call succeeding through SFU
- ✅ Bandwidth reduced by 50% vs. mesh

---

## Phase 2: Client Integration (Months 2-3)

### Goals
- Update iOS/Android/Web clients to use SFU
- Implement fallback to mesh for small calls
- Comprehensive client testing

### Work Items

#### 2.1 iOS Client Update
- **Framework**: WebRTC (already used)
- **Changes**:
  - Parse SFU URL from server
  - Connect to SFU via ICE
  - Handle single upstream + N downstream tracks
  - Implement bitrate adaptation

```swift
// Current (Mesh)
for participant in participants {
    let peerConnection = createPeerConnection()
    peerConnection.addTrack(localTrack)
    await exchangeSDP(participant)
}

// New (SFU)
let sfuConnection = createPeerConnection()
sfuConnection.addTrack(localTrack)  // Single upload

for participant in participants {
    sfuConnection.onTrack { remoteTrack in
        addRemoteView(remoteTrack, userId: participant.id)
    }
}
```

**Estimated Effort**: 25 days

#### 2.2 Android Client Update
- Similar to iOS implementation
- Use WebRTC SDK for Android
- Test on variety of devices

**Estimated Effort**: 25 days

#### 2.3 Web Client Update
- Update React/Vue components
- Implement adaptive streaming
- Test on various browsers/network conditions

**Estimated Effort**: 20 days

#### 2.4 Fallback Logic
- Detect if SFU is available
- For N ≤ 6: Use mesh (simpler, faster)
- For N > 6: Automatically switch to SFU
- Allow manual override for testing

**Estimated Effort**: 10 days

### Deliverables
- ✅ iOS/Android/Web clients support SFU
- ✅ Automatic fallback working correctly
- ✅ 20-user test call stable for 10+ minutes
- ✅ Battery drain < 12% per hour (iOS)

---

## Phase 3: Quality & Performance (Months 3-4)

### Goals
- Implement adaptive bitrate control
- Optimize for various network conditions
- Add bandwidth monitoring and alerts

### Work Items

#### 3.1 Bitrate Adaptation
- Monitor network conditions (RTT, packet loss)
- Dynamically adjust encoding quality
- Implement REMB (Receiver Estimated Maximum Bitrate)

```typescript
// Pseudocode: Bitrate Adaptation
function updateBitrate(networkStats) {
    if (packetLoss > 5%) {
        targetBitrate = currentBitrate * 0.8;  // Reduce by 20%
    } else if (packetLoss < 1% && rtt < 50ms) {
        targetBitrate = currentBitrate * 1.1;  // Increase by 10%
    }

    peerConnection.setSenders([{
        parameters: { encodings: [{ maxBitrate: targetBitrate }] }
    }]);
}
```

**Estimated Effort**: 20 days

#### 3.2 Bandwidth Monitoring
- Track per-participant bandwidth usage
- Alert if participant is consuming excessive bandwidth
- Implement participant priority system

**Estimated Effort**: 15 days

#### 3.3 Quality Metrics
- Monitor audio/video quality indicators:
  - MOS (Mean Opinion Score) for audio
  - PSNR (Peak Signal-to-Noise Ratio) for video
  - FPS, resolution, bitrate
- Send metrics to analytics backend

**Estimated Effort**: 15 days

### Deliverables
- ✅ Bitrate adapts automatically to network
- ✅ Video quality remains acceptable at 1 Mbps downlink
- ✅ Audio quality remains acceptable at 100 Kbps downlink
- ✅ Bandwidth usage dashboard in admin panel

---

## Phase 4: Scaling & Reliability (Months 4-6)

### Goals
- Support 50+ participants per call
- Implement redundancy and failover
- Global distribution of SFU servers

### Work Items

#### 4.1 Load Balancing
- Deploy multiple SFU instances behind load balancer
- Implement session affinity (user ↔ SFU mapping)
- Monitor SFU health and auto-scale

```
Load Balancer
     │
     ├─► SFU-1 (us-east-1)  ─ 32 participants
     ├─► SFU-2 (us-east-1)  ─ 28 participants
     ├─► SFU-3 (eu-west-1)  ─ 25 participants
     └─► SFU-4 (ap-south-1) ─ 30 participants
```

**Estimated Effort**: 25 days

#### 4.2 Geographic Distribution
- Deploy SFU servers in multiple regions
- Route clients to nearest SFU (latency-based)
- Handle cross-region participant scenarios

**Estimated Effort**: 20 days

#### 4.3 Redundancy & Failover
- Primary-backup SFU pairs
- Implement graceful connection migration
- Auto-failover with <5 second recovery time

**Estimated Effort**: 20 days

#### 4.4 Monitoring & Observability
- Prometheus metrics for SFU health
- Distributed tracing (Jaeger)
- Real-time alerting for:
  - SFU CPU > 80%
  - Packet loss > 2%
  - Latency > 300ms

**Estimated Effort**: 20 days

### Deliverables
- ✅ 50-participant call stable
- ✅ Global SFU deployment across 3+ regions
- ✅ Auto-failover tested and validated
- ✅ <100ms latency for all participants

---

## Phase 5: Advanced Features (Months 6-9)

### Goals
- Implement advanced SFU capabilities
- Add server-side effects and filters
- Implement recording and analytics

### Work Items

#### 5.1 Recording
- Server-side recording of all video/audio streams
- On-demand or scheduled recording
- Efficient storage (H.265 codec)
- Playback from cloud storage

**Estimated Effort**: 20 days

#### 5.2 Selective Forwarding
- Send only N-1 highest quality streams to each participant
- Drop lower quality streams if bandwidth constrained
- Ensure each participant sees all speakers in sequence

**Estimated Effort**: 15 days

#### 5.3 Server-Side Processing
- Detect active speaker
- Add dynamic backgrounds (Zoom-like)
- Apply virtual backgrounds
- Add real-time filters

**Estimated Effort**: 25 days

#### 5.4 Analytics & Reporting
- Per-call quality metrics
- Participant engagement metrics
- Network performance trends
- Cost per participant analysis

**Estimated Effort**: 20 days

### Deliverables
- ✅ Call recording with 100% frame accuracy
- ✅ Active speaker detection with < 500ms latency
- ✅ Virtual backgrounds available for 50+ participants
- ✅ Detailed analytics dashboard

---

## Budget Estimate

| Phase | Duration | Team Size | Cost | Deliverables |
|-------|----------|-----------|------|--------------|
| 1: Foundation | 2 months | 2 engineers | $40K | SFU infrastructure, signaling |
| 2: Client Integration | 2 months | 4 engineers | $80K | iOS/Android/Web SFU support |
| 3: Quality | 1.5 months | 2 engineers | $30K | Bitrate adaptation, metrics |
| 4: Scaling | 2.5 months | 3 engineers | $60K | Load balancing, geo-distribution |
| 5: Advanced | 3 months | 3 engineers | $60K | Recording, processing, analytics |
| **Total** | **9 months** | **~3 avg** | **$270K** | **Enterprise-grade SFU** |

---

## Risk Mitigation

### Risk 1: SFU Server Instability
**Probability**: Medium | **Impact**: High

**Mitigation**:
- Deploy in staging first (1-2 weeks)
- Load test with 100+ participants
- Have fallback to mesh for production calls
- Set strict SLA: 99.9% uptime

### Risk 2: Client Compatibility Issues
**Probability**: Medium | **Impact**: High

**Mitigation**:
- Test on 20+ device models
- Beta test with 100 real users
- Gradual rollout (10% → 50% → 100%)
- Quick rollback plan

### Risk 3: Network Latency
**Probability**: Low | **Impact**: Medium

**Mitigation**:
- Deploy SFU in all major regions
- Route based on network RTT
- Implement adaptive ICE candidate selection
- Monitor latency continuously

### Risk 4: Cost Overrun
**Probability**: Medium | **Impact**: Medium

**Mitigation**:
- Use open-source SFU (Janus) vs. commercial
- Optimize server utilization (max 70% CPU)
- Implement auto-scaling based on demand
- Regular cost audits

---

## Success Criteria

| Metric | Target | Current | Phase |
|--------|--------|---------|-------|
| Max participants | 50 | 8 | 4 |
| Latency (P95) | < 150ms | < 100ms | 3 |
| Audio quality (MOS) | > 4.2 | 4.3 | 3 |
| Uptime | 99.9% | 100% (testing) | 4 |
| Cost per hour | < $0.05/user | N/A | 5 |
| Setup time | < 3 sec | 1 sec | 2 |
| Battery drain | < 12% / hour | 15% / hour | 3 |

---

## Timeline Visualization

```
M1    M2    M3    M4    M5    M6    M7    M8    M9
├─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
  Phase 1         Phase 2       Phase 3     Phase 4
Foundation      Integration    Quality     Scaling
  ├────┤         ├────┤         ├──┤        ├─────┤
                                              Phase 5
                                            Advanced
                                            ├─────────┤
```

---

## Go/No-Go Decision Points

### End of Phase 1: Foundation
- **Criteria**:
  - ✅ SFU supports 20+ participants
  - ✅ Bandwidth reduced by 50%
  - ✅ < 200ms latency
  - ✅ Signaling protocol v2 working
- **Decision**: Proceed with client integration

### End of Phase 2: Client Integration
- **Criteria**:
  - ✅ iOS/Android/Web support SFU
  - ✅ Fallback to mesh working
  - ✅ 100 real user beta test successful
  - ✅ No critical bugs
- **Decision**: Begin production rollout

### End of Phase 3: Quality & Performance
- **Criteria**:
  - ✅ Bitrate adaptation working reliably
  - ✅ Video quality acceptable on 1 Mbps
  - ✅ Battery drain < 12% per hour
  - ✅ Metrics dashboard live
- **Decision**: Scale to 50 participants

### End of Phase 4: Scaling & Reliability
- **Criteria**:
  - ✅ 50-participant calls stable
  - ✅ Global SFU deployment
  - ✅ < 100ms latency globally
  - ✅ Auto-failover working
- **Decision**: Production release

---

## Post-Implementation Roadmap

### Year 2 Goals
1. **WebRTC Stats Enhancement**: More granular metrics
2. **ML-based Quality Prediction**: Predict call quality issues
3. **Conference Room Mode**: Dedicated layouts for large calls
4. **Translation**: Real-time translation of participants
5. **Recording Analytics**: Auto-generated summaries

### Year 3+ Vision
- Enterprise features (SSO, compliance)
- Hybrid on-prem + cloud deployment
- Advanced virtual backgrounds with body detection
- Gesture recognition and real-time reactions

---

## Conclusion

The migration from Mesh to SFU architecture is necessary to support large-scale group video calls (50+ participants) while maintaining quality and battery life. The phased approach minimizes risk, allows for iterative validation, and provides clear go/no-go decision points.

**Key Success Factor**: Maintaining backward compatibility with existing mesh-based calls during the transition.

---

**Document Version**: 1.0
**Last Updated**: October 29, 2025
**Owner**: Backend Engineering Team
**Status**: Ready for Approval
