//
//  MaleFemaleViewController.swift
//  Zonto
//
//  Created by Oleg Granchenko on 05.02.2020.
//  Copyright © 2020 Zonto. All rights reserved.
//

import UIKit

class MaleFemaleViewController: ZontoViewController {
    
    //MARK: - Property
    private var isChecked: Bool = false
    private let baseRegisterSetup = BaseRegisterSetup()
    private let isButton = false
    
    //MARK: - Outlets
    @IBOutlet weak var headerLabel: UILabel!
    @IBOutlet weak var maleButton: UIButton!
    @IBOutlet weak var femaleButton: UIButton!
    @IBOutlet weak var maleLabel: UILabel!
    @IBOutlet weak var femaleLabel: UILabel!
    @IBOutlet weak var furtherButton: UIButton!
    @IBOutlet weak var dateTextField: ATextField!
    
    // MARK:- Outlets action
    fileprivate func userDefaultsSet(_ sender: UIButton) {
        switch sender.tag {
        case 1:
            baseRegisterSetup.defaults.set(sender.tag, forKey: "Gender")
        default:
            baseRegisterSetup.defaults.set(sender.tag, forKey: "Gender")
        }
    }
    
    @IBAction func maleOrFemaleButtonTapped(_ sender: UIButton) {
        setupMaleFemaleButtons()
        sender.tintColor = .systemBlue
        userDefaultsSet(sender)
        sender.isSelected = true
        finalCheck()
    }
    
    @IBAction func furtherButtonPressed(_ sender: Any) {
        checkAndFurther()
        guard isChecked else { return }
        guard let vc = storyboard?.instantiateViewController(withIdentifier: "PasswordVC") as? PasswordViewController else {
            fatalError("Failed to load MaleFemaleViewController from storyboard.")
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    //MARK: - Setups
    fileprivate func setupNavBar() {
        viewTitle = localized("title_register", defaultString: "Registration")
    }
    
    fileprivate func setupMaleFemaleButtons() {
        let arr: [UIButton] = [maleButton, femaleButton]
        for button in arr {
            let image = button.currentImage?.withRenderingMode(.alwaysTemplate)
            button.setImage(image, for: .normal)
            button.tintColor = ColorCompatibility.secondarySystemFill
            button.layer.borderColor = ColorCompatibility.secondarySystemFill.cgColor
            button.layer.borderWidth = 2
            button.layer.cornerRadius = 4
            button.layer.masksToBounds = true
        }
    }
    
    fileprivate func setupFurtherButton() {
        baseRegisterSetup.baseSetupFurtherButton(furtherButton)
    }
    
    fileprivate func setUpTextField() {
        dateTextField.placeHolder.text = nil
        dateTextField.textField.attributedPlaceholder = NSAttributedString(string: localized("male_female_date_of_birth", defaultString: "Date of birth"), attributes: [
            .foregroundColor: ColorCompatibility.placeholderText,
            .font: UIFont.boldSystemFont(ofSize: 15.0)
        ])
        dateTextField.textField.contentVerticalAlignment = .center
        dateTextField.textField.textAlignment = .center
    }
    
    fileprivate func setupMaleFemaleLabels() {
        maleLabel.text = localized("male_female_male", defaultString: "Male")
        femaleLabel.text = localized("male_female_female", defaultString: "Female")
    }
    
    fileprivate func setupUI() {
        setupNavBar()
        headerLabel.text = localized("male_female_gender_and_dob", defaultString: "Your gender and date of birth")
        setupMaleFemaleButtons()
        setupMaleFemaleLabels()
        setUpTextField()
        setupFurtherButton()
    }
    
    // MARK:- View Controller methods
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        dateTextField.textField.setInputViewDatePicker(target: self, selector: #selector(tapDone))
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationItem.backBarButtonItem = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)
    }
    
    fileprivate func setFormatForServer(_ dateformatter: DateFormatter, _ datePicker: UIDatePicker) {
        dateformatter.dateFormat = "YYYY-MM-dd"
        let dob = dateformatter.string(from: datePicker.date)
        baseRegisterSetup.defaults.set(dob, forKey: "Dob")
    }
    
    @objc func tapDone() {
        if let datePicker = dateTextField.textField.inputView as? UIDatePicker {
            let dateformatter = DateFormatter()
            dateformatter.dateStyle = .medium
            dateTextField.text = dateformatter.string(from: datePicker.date)
            
            setFormatForServer(dateformatter, datePicker)
            
        }
        dateTextField.separator.backgroundColor = ColorCompatibility.secondarySystemFill
        finalCheck()
        dateTextField.textField.resignFirstResponder()
    }
    
    fileprivate func validationPersonImage() {
        let arr: [UIButton] = [maleButton, femaleButton]
        guard arr.filter({$0.isSelected}).isEmpty else { return }
        arr.forEach { (button) in
            button.layer.borderColor = UIColor.systemRed.cgColor
            button.layer.borderWidth = 2
            button.shake(count: 4, for: 0.3, withTranslation: 1)
        }
    }
    
    fileprivate func validationDateTF() {
        guard dateTextField.text!.isEmpty else { return }
        dateTextField.separator.backgroundColor = UIColor.systemRed
        dateTextField.shake()
    }
    
    fileprivate func finalCheck() {
        guard ![maleButton, femaleButton].filter({$0.isSelected}).isEmpty && !dateTextField.text!.isEmpty else { return }
        furtherButton.setTitleColor(.systemBlue, for: .normal)
        isChecked = true
    }
    
    fileprivate func checkAndFurther() {
        validationPersonImage()
        validationDateTF()
    }
}
