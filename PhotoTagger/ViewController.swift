//
//  ViewController.swift
//  PhotoTagger
//
//  Created by Marco Antonio Gutierrez López on 4/16/18.
//  Copyright © 2018 Razeware LLC. All rights reserved.
//

import UIKit
import Alamofire

class ViewController: UIViewController {

  // MARK: - IBOutlets
  @IBOutlet var takePictureButton: UIButton!
  @IBOutlet var imageView: UIImageView!
  @IBOutlet var progressView: UIProgressView!
  @IBOutlet var activityIndicatorView: UIActivityIndicatorView!

  // MARK: - Properties
  fileprivate var tags: [String]?
  fileprivate var colors: [PhotoColor]?

  // MARK: - View Life Cycle
  override func viewDidLoad() {
    super.viewDidLoad()

    guard !UIImagePickerController.isSourceTypeAvailable(.camera) else { return }

    takePictureButton.setTitle("Select Photo", for: .normal)
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)

    imageView.image = nil
  }

  // MARK: - Navigation
  override func prepare(for segue: UIStoryboardSegue, sender: Any?) {

    if segue.identifier == "ShowResults" {
      let controller = segue.destination as! TagsColorsViewController
      controller.tags = tags
      controller.colors = colors
    }
  }

  // MARK: - IBActions
  @IBAction func takePicture(_ sender: UIButton) {
    let picker = UIImagePickerController()
    picker.delegate = self
    picker.allowsEditing = false

    if UIImagePickerController.isSourceTypeAvailable(.camera) {
      picker.sourceType = .camera
    } else {
      picker.sourceType = .photoLibrary
      picker.modalPresentationStyle = .fullScreen
    }

    present(picker, animated: true)
  }
}

// MARK: - UIImagePickerControllerDelegate
extension ViewController: UIImagePickerControllerDelegate {

  func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String: Any]) {
    guard let image = info[UIImagePickerControllerOriginalImage] as? UIImage else {
      print("Info did not have the required UIImage for the Original Image")
      dismiss(animated: true)
      return
    }

    imageView.image = image
    // 1
    takePictureButton.isHidden = true
    progressView.progress = 0.0
    progressView.isHidden = false
    activityIndicatorView.startAnimating()
    
    upload(
      image: image,
      progressCompletion: { [unowned self] percent in
        // 2
        self.progressView.setProgress(percent, animated: true)
      },
      completion: { [unowned self] tags, colors in
        // 3
        self.takePictureButton.isHidden = false
        self.progressView.isHidden = true
        self.activityIndicatorView.stopAnimating()
        
        self.tags = tags
        self.colors = colors
        
        // 4
        self.performSegue(withIdentifier: "ShowResults", sender: self)
    })
    dismiss(animated: true)
  }
}

// MARK: - UINavigationControllerDelegate
extension ViewController: UINavigationControllerDelegate {
}

// Networking calls
extension ViewController {
  func upload(image: UIImage,
              progressCompletion: @escaping (_ percent: Float) -> Void,
              completion: @escaping (_ tags: [String], _ colors: [PhotoColor]) -> Void) {
    guard let imageData = UIImageJPEGRepresentation(image, 0.5) else {
      print("Could not get JPEG representation of UIImage")
      return
    }
    Alamofire.upload(
      multipartFormData: { multipartFormData in
        multipartFormData.append(imageData,
                                 withName: "imagefile",
                                 fileName: "image.jpg",
                                 mimeType: "image/jpeg")
    },
      with: ImaggaRouter.content,
      encodingCompletion: { encodingResult in
        switch encodingResult {
        case .success(let upload, _, _):
          upload.uploadProgress { progress in
            progressCompletion(Float(progress.fractionCompleted))
          }
          upload.validate()
          upload.responseJSON { response in
            // 1.
            guard response.result.isSuccess else {
              print("Error while uploading file: \(String(describing: response.result.error))")
              completion([String](), [PhotoColor]())
              return
            }
            
            // 2.
            guard let responseJSON = response.result.value as? [String: Any],
              let uploadedFiles = responseJSON["uploaded"] as? [[String: Any]],
              let firstFile = uploadedFiles.first,
              let firstFileID = firstFile["id"] as? String else {
                print("Invalid information received from service")
                completion([String](), [PhotoColor]())
                return
            }
            
            print("Content uploaded with ID: \(firstFileID)")
            
            // 3.
            self.downloadTags(contentID: firstFileID) { tags in
              self.downloadColors(contentID: firstFileID) { colors in
                completion(tags, colors)
              }
            }
          }
        case .failure(let encodingError):
          print(encodingError)
        }
    }
    )
  }
  func downloadTags(contentID: String, completion: @escaping ([String]) -> Void) {
    Alamofire.request(ImaggaRouter.tags(contentID))
      .responseJSON { response in
        // 1.
        guard response.result.isSuccess else {
          print("Error while fetching tags: \(String(describing: response.result.error))")
          completion([String]())
          return
        }
        
        // 2.
        guard let responseJSON = response.result.value as? [String: Any],
          let results = responseJSON["results"] as? [[String: Any]],
          let firstObject = results.first,
          let tagsAndConfidences = firstObject["tags"] as? [[String: Any]] else {
            print("Invalid tag information received from the service")
            completion([String]())
            return
        }
        
        // 3.
        let tags = tagsAndConfidences.flatMap({ dict in
          return dict["tag"] as? String
        })
        
        // 4.
        completion(tags)
    }
  }
  func downloadColors(contentID: String, completion: @escaping ([PhotoColor]) -> Void) {
    Alamofire.request(ImaggaRouter.colors(contentID))
      .responseJSON { response in
        // 2.
        guard response.result.isSuccess else {
          print("Error while fetching colors: \(String(describing: response.result.error))")
          completion([PhotoColor]())
          return
        }
        
        // 3.
        guard let responseJSON = response.result.value as? [String: Any],
          let results = responseJSON["results"] as? [[String: Any]],
          let firstResult = results.first,
          let info = firstResult["info"] as? [String: Any],
          let imageColors = info["image_colors"] as? [[String: Any]] else {
            print("Invalid color information received from service")
            completion([PhotoColor]())
            return
        }
        
        // 4.
        let photoColors = imageColors.flatMap({ (dict) -> PhotoColor? in
          guard let r = dict["r"] as? String,
            let g = dict["g"] as? String,
            let b = dict["b"] as? String,
            let closestPaletteColor = dict["closest_palette_color"] as? String else {
              return nil
          }
          
          return PhotoColor(red: Int(r),
                            green: Int(g),
                            blue: Int(b),
                            colorName: closestPaletteColor)
        })
        
        // 5.
        completion(photoColors)
    }
  }
}

