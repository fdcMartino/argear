//
//  MainBottomFunctionView.swift
//  ARGearSample
//
//  Created by Jihye on 2020/01/30.
//  Copyright © 2020 Seerslab. All rights reserved.
//

import UIKit
import ARGear

enum MainBottomButtonType : Int {
    case Beauty = 0
    case Filter = 1
    case Content = 2
    case Bulge = 3
}

//protocol MainBottomFunctionDelegate: class {
//    func photoButtonAction(_ button: UIButton)
//    func videoButtonAction(_ button: UIButton)
//}

class MainBottomFunctionView: UIView {

    let kMainBottomFunctionFilterButtonName = "icFilter"
    let kMainBottomFunctionContentButtonName = "icSticker"
    let kMainBottomFunctionRecordTimeLabelRatioFullColor = UIColor.white
   
    // weak var delegate: MainBottomFunctionDelegate?

    @IBOutlet weak var touchCancelView: UIView!
    @IBOutlet weak var filterButton: UIButton!
    @IBOutlet weak var filterView: FilterView!
    
    private var argObservers = [NSKeyValueObservation]()

    override func awakeFromNib() {
        super.awakeFromNib()
        
        self.setRatio(ARGMediaRatio(rawValue: self.tag) ?? ._4x3)
        
      
    }
    
    deinit {
        self.removeObservers()
    }
    
    
    func removeObservers() {
        self.argObservers.removeAll()
    }
    
    func setRatio(_ ratio: ARGMediaRatio) {
        
        self.setButtonsImage(ratio: ratio)
        self.filterView.setRatio(ratio)

    }
    
    func setButtonsImage(ratio: ARGMediaRatio) {
        
        var filterButtonImageName = self.kMainBottomFunctionFilterButtonName
        
        var imageColorString = ""
        if ratio == ._16x9 {
            imageColorString = "White"
        } else {
            imageColorString = "Black"
        }
        
        filterButtonImageName.append(imageColorString)
        filterButtonImageName.append("_".appendLanguageCode())
 
        self.filterButton.setImage(UIImage(named: filterButtonImageName), for: .normal)
        self.filterButton.setImage(UIImage(named: filterButtonImageName)?.withAlpha(BUTTON_HIGHLIGHTED_ALPHA), for: .highlighted)


    }
    
    @IBAction func handleTapFrom(_ tap: UITapGestureRecognizer) {
        if tap.state == .ended {
            self.closeBottomFunctions()
        }
    }
    
    @IBAction func bottomButtonAction(_ sender: UIButton) {
        
        self.openBottomFunctions()
        let buttonType = MainBottomButtonType(rawValue: sender.tag)
        
        switch buttonType {
        case .Filter:
            self.filterView.open()
        default:
            break
        }
    }
    
    func openBottomFunctions() {
        self.touchCancelView.isHidden = false
        
        self.isHidden = true
    }
    
    func closeBottomFunctions() {
        self.touchCancelView.isHidden = true
        self.filterView.close()
        self.isHidden = false
    }
    
}
