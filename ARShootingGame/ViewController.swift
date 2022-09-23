//
//  ViewController.swift
//  ARShootingGame
//
//  Created by kimhyeongmin on 2022/09/02.
//

import UIKit
import ARKit
import Vision
import Foundation


enum BitMaskCategory: Int {
	case bullet = 2
	case target = 3
}

@available(iOS 14.0, *)
class ViewController: UIViewController, ARSCNViewDelegate, SCNPhysicsContactDelegate, ARCoachingOverlayViewDelegate {
	
	@IBOutlet var sceneView: ARSCNView!
	
	var power: Float = 100   // bullet 속도 조절
	var Target: SCNNode?
	
	let configuration = ARWorldTrackingConfiguration()
	
	//Store The Rotation Of The CurrentNode
	var currentAngleY: Float = 0.0
	
	private var distance: Float = 0
	var isRotating = false
	var state: String = ""
	private var handPoseRequest = VNDetectHumanHandPoseRequest()
	var currentFingerPosition: CGPoint?
	
	// Ray-casting을 위한 Kalman filter
	// var measurements_1: [Double] = []
	// var filter_1 = KalmanFilter(stateEstimatePrior: 0.0, errorCovariancePrior: 1)
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		// 뷰 델리게이트 설정
		sceneView.delegate = self
		
		let gunNode = addGun(position: SCNVector3(0,0,-0.5), name: "colt")
		
		sceneView.scene.rootNode.addChildNode(gunNode)
		
		sceneView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
		sceneView.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handleMove(_:))))
		sceneView.addGestureRecognizer(UIRotationGestureRecognizer(target: self, action: #selector(handleRotate(_:))))
		
		sceneView.session.run(configuration)

//		self.sceneView.debugOptions = [ARSCNDebugOptions.showWorldOrigin, ARSCNDebugOptions.showFeaturePoints]

		self.sceneView.autoenablesDefaultLighting = true
		self.sceneView.scene.physicsWorld.contactDelegate = self
	}
	
	// 모든 것을 새로운 노드로 그룹화하여 더 쉽게 관리를 위한 메서드
	// --------------------- 사용 안되고 있음 -----------------------
	func getMyNodes() -> [SCNNode] {
		var nodes: [SCNNode] = [SCNNode]()
		for node in sceneView.scene.rootNode.childNodes {
			nodes.append(node)
		}
		return nodes
	}
	// --------------------- 사용 안되고 있음 -----------------------

	
	func addGun(position: SCNVector3, name: String) -> SCNNode{
		let gunScene = SCNScene(named: "art.scnassets/colt.scn")!
		let gunNode = gunScene.rootNode.childNode(withName: "colt", recursively: false)
		gunNode?.position = position
		return gunNode!
	}
	
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		
	}
	
	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		
		// View의 세션 일시 중지
		sceneView.session.pause()
	}
	
	
	func session(_ session: ARSession, didFailWithError error: Error) {
		// 사용자에게 오류 메시지 표시
		print("session failed")
	}
	
	func sessionWasInterrupted(_ session: ARSession) {
		// 오버레이를 표시하여 세션이 중단되었음 등을 알리는 용도
		
	}
	
	func sessionInterruptionEnded(_ session: ARSession) {
		// 일관된 추적이 필요한 경우 추적 재설정 및/또는 기존 앵커 제거
		
	}
	
	func move_node(location:SCNVector3, nodeHit:SCNNode){
		let action = SCNAction.move(to: location, duration: 1)
		nodeHit.runAction(action)
	}
	
	// Tap gesture
	@objc func handleTap(_ gesture: UITapGestureRecognizer) {
		guard let sceneView = gesture.view as? ARSCNView else { return }
		guard let pointOfView = sceneView.pointOfView else { return }
		let transform = pointOfView.transform
		let orientation = SCNVector3(-transform.m31, -transform.m32, -transform.m33)
		let tapLocation = SCNVector3(transform.m41, transform.m42, transform.m43)
		let position = orientation + tapLocation
		
		let bullet = SCNNode(geometry: SCNSphere(radius: 0.1))
		bullet.geometry?.firstMaterial?.diffuse.contents = UIColor.gray
		bullet.position = position
		
		// type: .dynamic -> 움직이는 물리 오브젝트
		let body = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(node: bullet, options: nil))
		body.isAffectedByGravity = true    // body에 중력 효과
		bullet.physicsBody = body
		bullet.physicsBody?.applyForce(SCNVector3(orientation.x*power, orientation.y*power, orientation.z*power), asImpulse: true)  // direction 과 asImpulse: true(즉각 반응) 설정
		
		bullet.physicsBody?.categoryBitMask = BitMaskCategory.bullet.rawValue
		bullet.physicsBody?.contactTestBitMask = BitMaskCategory.target.rawValue
		
		self.sceneView.scene.rootNode.addChildNode(bullet)
		
		// 오브젝트 충돌(runAction) 시 bullet이 2초 후 사라지도록
		bullet.runAction(SCNAction.sequence([SCNAction.wait(duration: 2.0), SCNAction.removeFromParentNode()]))
	}
	
	// pan gesture
	@objc func handleMove(_ gesture: UIPanGestureRecognizer) {
		
		//1. 현재 터치 포인트
		let location = gesture.location(in: self.sceneView)
		
		//2. 다음 기능 포인트 등
		guard let nodeHitTest = self.sceneView.hitTest(location, options: nil).first else { print("no node"); return }
		
		let nodeHit = nodeHitTest.node
		let original_x = nodeHitTest.node.position.x
		let original_y = nodeHitTest.node.position.y
		
		//3. 월드 좌표로 변환
		let worldTransform = nodeHitTest.simdWorldCoordinates
		
		//4. 노드에 적용
		nodeHit.position = SCNVector3(worldTransform.x, worldTransform.y, -0.5)
		
		for node in nodeHit.parent!.childNodes {
			if node.name != nodeHit.name {
				let old_x = node.position.x
				let old_y = node.position.y
				node.position = SCNVector3((nodeHit.simdPosition.x - original_x + old_x), (nodeHit.simdPosition.y - original_y + old_y), -0.5)
			}
		}
	}
	
	// Rotate action
	@objc func handleRotate(_ gesture: UIRotationGestureRecognizer) {
		let location = gesture.location(in: sceneView)
		guard let nodeHitTest = self.sceneView.hitTest(location, options: nil).first else { print("no node"); return }
		let nodeHit = nodeHitTest.node
		//call rotation method here
		if gesture.state == UIGestureRecognizer.State.changed {
			//1. 제스처에서 현재 회전 가져오기
			let rotation = Float(gesture.rotation)
			print(rotation)
			
			//2. 제스처 상태가 변경된 경우 노드 오일러 각도 설정.y
			if gesture.state == .changed{
				isRotating = true
				nodeHit.eulerAngles.y = currentAngleY + rotation
			}
			
			//3. 제스처가 종료된 경우 오브젝트의 마지막 각도 저장
			if(gesture.state == .ended) {
				currentAngleY = nodeHit.eulerAngles.y
				isRotating = false
			}
		} else {
			// nothing
		}
	}
	
	@IBAction func addTargets(_ sender: Any) {
		for _ in 0...2 {
			let xposition = Float.random(in: 0...10) - Float.random(in: 0...10)
			let yposition = Float.random(in: 0...5)
			let zposition = -Float.random(in: 20 ... 40)
			addtarget(x: xposition, y: yposition, z: zposition)
		}
	}
	
	func addtarget(x: Float, y: Float, z: Float) {
		let targetScene = SCNScene(named: "art.scnassets/targeting.scn")
		let targetNode = (targetScene?.rootNode.childNode(withName: "targeting", recursively: false))!
		targetNode.position = SCNVector3(x,y,z)
		
		// target과 bullet 이 collide 를 일으킬 수 있도록 type: .static 설정
		// 두 targetNode 사이의 contact detection 을 수행하기 위해 shape: SCNPhysicsShape(node: eggNode, options: nil) 지정
		targetNode.physicsBody = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(node: targetNode, options: nil))
		
		targetNode.physicsBody?.categoryBitMask = BitMaskCategory.target.rawValue
		targetNode.physicsBody?.contactTestBitMask = BitMaskCategory.bullet.rawValue
		
		self.sceneView.scene.rootNode.addChildNode(targetNode)
	}
	
	// 두 오브젝트의 충돌을 감지할 때 마다 불러오는 함수
	func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
		let nodeA = contact.nodeA
		let nodeB = contact.nodeB
		
		if nodeA.physicsBody?.categoryBitMask == BitMaskCategory.target.rawValue {
			self.Target = nodeA
		} else if nodeB.physicsBody?.categoryBitMask == BitMaskCategory.target.rawValue {
			self.Target = nodeB
		}
		
		// target이 충돌했을 때 particle 애니메이션 실행
		let confetti = SCNParticleSystem(named: "art.scnassets/Fire.scnp", inDirectory: nil)
		confetti?.loops = false // 반복하지 않음
		confetti?.particleLifeSpan = 3  // 4초간 지속
		confetti?.emitterShape = Target?.geometry   // Target 오브젝트를 바운더리로 애니메이션 실행
		let confettiNode = SCNNode()
		confettiNode.addParticleSystem(confetti!)
		confettiNode.position = contact.contactPoint    // 위치 지정
		self.sceneView.scene.rootNode.addChildNode(confettiNode)
		Target?.removeFromParentNode()  // 충돌 시 삭제
	}
	
	// MARK: Methods
	
	func updateCoreML() {
		// Get Camera Image as RGB
		let pixbuff : CVPixelBuffer? = (sceneView.session.currentFrame?.capturedImage)
		if pixbuff == nil {
			self.state = "no camera"
			return }
		let ciImage = CIImage(cvPixelBuffer: pixbuff!)
		
		var thumbTip: CGPoint?
		var thumbIp: CGPoint?
		var thumbMp: CGPoint?
		var thumbCmc: CGPoint?
		
		var indexTip: CGPoint?
		var indexDip: CGPoint?
		var indexPip: CGPoint?
		var indexMcp: CGPoint?
		
		var middleTip: CGPoint?
		var middleDip: CGPoint?
		var middlePip: CGPoint?
		var middleMcp: CGPoint?
		
		var ringTip: CGPoint?
		var ringDip: CGPoint?
		var ringPip: CGPoint?
		var ringMcp: CGPoint?
		
		var littleTip: CGPoint?
		var littleDip: CGPoint?
		var littlePip: CGPoint?
		var littleMcp: CGPoint?
				
		let scale = CMTimeScale(NSEC_PER_SEC)
		let pts = CMTime(value: CMTimeValue(sceneView.session.currentFrame!.timestamp * Double(scale)),
						 timescale: scale)
		var timingInfo = CMSampleTimingInfo(duration: CMTime.invalid,
											presentationTimeStamp: pts,
											decodeTimeStamp: CMTime.invalid)
		
		let CMFCV = CMFormatDescription.make(from: pixbuff!)!
		let CMSCV = CMSampleBuffer.make(from: pixbuff!, formatDescription: CMFCV, timingInfo: &timingInfo)
		let handler = VNImageRequestHandler(cmSampleBuffer: CMSCV!, orientation: .right, options: [:])
		do {
			// Perform VNDetectHumanHandPoseRequest
			try handler.perform([handPoseRequest])
			// Continue only when a hand was detected in the frame.
			// Since we set the maximumHandCount property of the request to 1, there will be at most one observation.
			guard let observation = handPoseRequest.results?.first else {
				self.state = "no hand"
				return
			}
			// Get points for thumb and index finger.
			let thumbPoints = try observation.recognizedPoints(VNHumanHandPoseObservation.JointsGroupName.thumb)
			let indexFingerPoints = try observation.recognizedPoints(VNHumanHandPoseObservation.JointsGroupName.indexFinger)
			let middleFingerPoints = try observation.recognizedPoints(VNHumanHandPoseObservation.JointsGroupName.middleFinger)
			let ringFingerPoints = try observation.recognizedPoints(VNHumanHandPoseObservation.JointsGroupName.ringFinger)
			let littleFingerPoints = try observation.recognizedPoints(VNHumanHandPoseObservation.JointsGroupName.littleFinger)
			
			// Look for tip points.
			guard let thumbTipPoint = thumbPoints[VNHumanHandPoseObservation.JointName.thumbTip],
				  let thumbIpPoint = thumbPoints[VNHumanHandPoseObservation.JointName.thumbIP],
				  let thumbMpPoint = thumbPoints[VNHumanHandPoseObservation.JointName.thumbMP],
				  let thumbCMCPoint = thumbPoints[VNHumanHandPoseObservation.JointName.thumbCMC] else {
				self.state = "no thumb"
				return
			}
			
			guard let indexTipPoint = indexFingerPoints[VNHumanHandPoseObservation.JointName.indexTip],
				  let indexDipPoint = indexFingerPoints[VNHumanHandPoseObservation.JointName.indexDIP],
				  let indexPipPoint = indexFingerPoints[VNHumanHandPoseObservation.JointName.indexPIP],
				  let indexMcpPoint = indexFingerPoints[VNHumanHandPoseObservation.JointName.indexMCP] else {
				self.state = "no index"
				return
			}
			
			guard let middleTipPoint = middleFingerPoints[VNHumanHandPoseObservation.JointName.middleTip],
				  let middleDipPoint = middleFingerPoints[VNHumanHandPoseObservation.JointName.middleDIP],
				  let middlePipPoint = middleFingerPoints[VNHumanHandPoseObservation.JointName.middlePIP],
				  let middleMcpPoint = middleFingerPoints[VNHumanHandPoseObservation.JointName.middleMCP] else {
				self.state = "no middle"
				return
			}
			
			guard let ringTipPoint = ringFingerPoints[VNHumanHandPoseObservation.JointName.ringTip],
				  let ringDipPoint = ringFingerPoints[VNHumanHandPoseObservation.JointName.ringDIP],
				  let ringPipPoint = ringFingerPoints[VNHumanHandPoseObservation.JointName.ringPIP],
				  let ringMcpPoint = ringFingerPoints[VNHumanHandPoseObservation.JointName.ringMCP] else {
				self.state = "no ring"
				return
			}
			
			guard let littleTipPoint = littleFingerPoints[VNHumanHandPoseObservation.JointName.littleTip],
				  let littleDipPoint = littleFingerPoints[VNHumanHandPoseObservation.JointName.littleDIP],
				  let littlePipPoint = littleFingerPoints[VNHumanHandPoseObservation.JointName.littlePIP],
				  let littleMcpPoint = littleFingerPoints[VNHumanHandPoseObservation.JointName.littleMCP] else {
				self.state = "no little"
				return
			}
			
			// Convert points from Vision coordinates to AVFoundation coordinates.
			thumbTip = CGPoint(x: thumbTipPoint.location.x, y: 1 - thumbTipPoint.location.y)
			thumbIp = CGPoint(x: thumbIpPoint.location.x, y: 1 - thumbIpPoint.location.y)
			thumbMp = CGPoint(x: thumbMpPoint.location.x, y: 1 - thumbMpPoint.location.y)
			thumbCmc = CGPoint(x: thumbCMCPoint.location.x, y: 1 - thumbCMCPoint.location.y)
			
			indexTip = CGPoint(x: indexTipPoint.location.x, y: 1 - indexTipPoint.location.y)
			indexDip = CGPoint(x: indexDipPoint.location.x, y: 1 - indexDipPoint.location.y)
			indexPip = CGPoint(x: indexPipPoint.location.x, y: 1 - indexPipPoint.location.y)
			indexMcp = CGPoint(x: indexMcpPoint.location.x, y: 1 - indexMcpPoint.location.y)
			
			middleTip = CGPoint(x: middleTipPoint.location.x, y: 1 - middleTipPoint.location.y)
			middleDip = CGPoint(x: middleDipPoint.location.x, y: 1 - middleDipPoint.location.y)
			middlePip = CGPoint(x: middlePipPoint.location.x, y: 1 - middlePipPoint.location.y)
			middleMcp = CGPoint(x: middleMcpPoint.location.x, y: 1 - middleMcpPoint.location.y)
			
			ringTip = CGPoint(x: ringTipPoint.location.x, y: 1 - ringTipPoint.location.y)
			ringDip = CGPoint(x: ringDipPoint.location.x, y: 1 - ringDipPoint.location.y)
			ringPip = CGPoint(x: ringPipPoint.location.x, y: 1 - ringPipPoint.location.y)
			ringMcp = CGPoint(x: ringMcpPoint.location.x, y: 1 - ringMcpPoint.location.y)
			
			littleTip = CGPoint(x: littleTipPoint.location.x, y: 1 - littleTipPoint.location.y)
			littleDip = CGPoint(x: littleDipPoint.location.x, y: 1 - littleDipPoint.location.y)
			littlePip = CGPoint(x: littlePipPoint.location.x, y: 1 - littlePipPoint.location.y)
			littleMcp = CGPoint(x: littleMcpPoint.location.x, y: 1 - littleMcpPoint.location.y)
			
			
			let middlePipTouched = VNImagePointForNormalizedPoint(middlePip!, Int(self.sceneView.bounds.size.width), Int(self.sceneView.bounds.size.height))
			self.state = "normal"
			
			// Translation using hand gesture
			guard let nodeHitTest = self.sceneView.hitTest(middlePipTouched, options: nil).first else { return }
			
			let nodeHit = nodeHitTest.node
			//3. Convert To World Coordinates
			let worldTransform = nodeHitTest.simdWorldCoordinates
			//4. Apply To The Node
			nodeHit.position = SCNVector3(worldTransform.x, worldTransform.y, -0.5)
			
			//  회전 및 변환은 손 제스처 분류기를 더 추가해야 함
			//            guard let nodeHitTest = self.sceneView.hitTest(thumbMpTouched, options: nil).first else { print("no node"); return }
			//            let nodeHit = nodeHitTest.node
			//            //call rotation method here
			//
			//            //2. If The Gesture State Has Changed Set The Nodes EulerAngles.y
			//            nodeHit.eulerAngles.y = currentAngleY + 0.1
			//            currentAngleY += 0.1
			//            print(nodeHit.eulerAngles.y )
			
		} catch {
			let error = (error)
			print(error)
		}
	}
	
	
	// ray cast method possible implementation
	//        guard let query = sceneView.raycastQuery(from: location, allowing: .existingPlaneInfinite, alignment: .any) else {
	//           return
	//        }
	//
	//        let results = sceneView.session.raycast(query)
	//        guard let hitTestResult = results.first else {
	//           print("No surface found")
	//           return
	//        }
	//        print(hitTestResult)
	
	//        let results = self.sceneView.hitTest(gesture.location(in: gesture.view), types: ARHitTestResult.ResultType.featurePoint)
	//        guard let result: ARHitTestResult = results.first else {
	//            return
	//        }
	//        let tappedNode = self.sceneView.hitTest(gesture.location(in: gesture.view), options: [:])
	//
	//        if !tappedNode.isEmpty {
	//            let node = tappedNode[0].node
	////            print(node)
	//
	//        } else {
	//
	//            return
	//
	//        }
	
	
	// MARK: - SCNSceneRendererDelegate
	// Vision 프레임워크가 TimeInterval마다 호출되서 실시간으로 손 감지
	func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
		DispatchQueue.main.async {
			self.updateCoreML()
		}
	}
	
}
// MARK: - ARSCNViewDelegate

// Override to create and configure nodes for anchors added to the view's session.
@available(iOS 14.0, *)
extension ViewController {
	func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) {
		
	}
	
	func renderer(_ renderer: SCNSceneRenderer, updateAtTime scene: SCNScene, atTime time: TimeInterval) {
		
	}
}

extension CMSampleBuffer {
	static func make(from pixelBuffer: CVPixelBuffer, formatDescription: CMFormatDescription, timingInfo: inout CMSampleTimingInfo) -> CMSampleBuffer? {
		var sampleBuffer: CMSampleBuffer?
		CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, dataReady: true, makeDataReadyCallback: nil,
										   refcon: nil, formatDescription: formatDescription, sampleTiming: &timingInfo, sampleBufferOut: &sampleBuffer)
		return sampleBuffer
	}
}

extension CMFormatDescription {
	static func make(from pixelBuffer: CVPixelBuffer) -> CMFormatDescription? {
		var formatDescription: CMFormatDescription?
		CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &formatDescription)
		return formatDescription
	}
}

// MARK:- ARSessionDelegate

@available(iOS 14.0, *)
extension ViewController: ARSessionDelegate {
	func session(_ session: ARSession, didUpdate frame: ARFrame) {
		//        updateCoreML()
	}
	
}

func + (left: SCNVector3, right: SCNVector3) -> SCNVector3 {
   return SCNVector3Make(left.x + right.x, left.y + right.y, left.z + right.z)
}
