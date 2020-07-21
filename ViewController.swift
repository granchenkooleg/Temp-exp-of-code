//
//  ViewController.swift
//  EqualizerView
//
//  Created by Oleg Granchenko on 07.07.2020.
//  Copyright © 2020 Oleg Granchenko. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    
    private var stackView = UIStackView()
    public static let countEQViews: Int = 30
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupSlider()
        setupStackView()
    }
    
    private func createViews(_ height: CGFloat) -> UIView {
        let viewEq = PlainHorizontalProgressBar()
        viewEq.color = .blue
        viewEq.backgroundColor = .gray
        viewEq.widthAnchor.constraint(equalToConstant: 5).isActive = true
        viewEq.heightAnchor.constraint(equalToConstant: height).isActive = true
        return viewEq
    }
    
    private func addViewsToStack()  {
        for num in 1...Self.countEQViews {
            if (num % 2 == 0) {
                stackView.addArrangedSubview(createViews(30))
            } else {
                stackView.addArrangedSubview(createViews(50))
            }
        }
    }
    
    private func setupStackView() {
        self.view.addSubview(stackView)
        stackView.axis  = NSLayoutConstraint.Axis.horizontal
        stackView.distribution = UIStackView.Distribution.equalSpacing
        stackView.alignment = UIStackView.Alignment.center
        stackView.spacing = 3.0
        
        addViewsToStack()
        
        //Constraints
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.centerXAnchor.constraint(equalTo: self.view.centerXAnchor).isActive = true
        stackView.centerYAnchor.constraint(equalTo: self.view.centerYAnchor).isActive = true
    }
}

extension ViewController {
    
    /// Create slider
    private func setupSlider() {
        let slider = UISlider(frame:CGRect(x: 50, y: 100, width: 250, height: 20))
        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.isContinuous = true
        slider.tintColor = UIColor.green
        slider.addTarget(self, action: #selector(ViewController.sliderValueDidChange(_:)), for: .valueChanged)
        view.addSubview(slider)
    }
    
    @objc private func sliderValueDidChange(_ sender:UISlider!) {
        let progress = CGFloat(sender.value)
        
        let diffValue = CGFloat(1) / CGFloat(Self.countEQViews)
        let _ = stackView.subviews.enumerated().map({ ($1 as? PlainHorizontalProgressBar)?.progress = (progress - CGFloat($0) * diffValue) * CGFloat(Self.countEQViews)})
    }
}
