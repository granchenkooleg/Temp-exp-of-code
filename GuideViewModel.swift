//
//  GuideViewModel.swift
//  Unwayl
//
//  Created by Oleg Granchenko on 27/05/2019.
//  Copyright © 2019 Oleg Granchenko. All rights reserved.
//


import RxCocoa
import RxSwift

final class GuideViewModel {
    typealias Video = (videoUrl: URL, isFullScreen: Bool)
    
    // MARK: - Properties
    // Public
    let userCollections = BehaviorRelay<Array<Wish>>(value: [])
    let otherCollections = BehaviorRelay<Array<Wish>>(value: [])
    let viewDidLoad = PublishSubject<Void>()
    let viewWillAppear = PublishSubject<Void>()
    let playButton = PublishSubject<Void>()
    let cellPlayButton = PublishSubject<Guide>()
    let guides = BehaviorRelay<Array<Guide>?>(value: [])
    let personalExcursions = BehaviorRelay<Array<AuthorExcursion>>(value: [])
    var personalExcursionsLocalVal = [AuthorExcursion]()
    let selectedCollection = BehaviorRelay<Wish?>(value: nil)
    let video = PublishSubject<Video>()
    
    // Private
    private let disposeBag = DisposeBag()
    
    init() {
        subscribe()
    }
    
    func deselectCategories() {
        let userC = userCollections.value.map { c -> Wish in
            var collection = c
            collection.isSelected = false
            return collection
        }
        let otherC = otherCollections.value.map { c -> Wish in
            var collection = c
            collection.isSelected = false
            return collection
        }
        
        userCollections.accept(userC)
        otherCollections.accept(otherC)
        
    }
}


// MARK: - Rx
extension GuideViewModel {
    private func subscribe() {
        viewDidLoad.asObservable()
            .subscribe(onNext: { [unowned self] in
                // MARK: - Collections of excursions
                self.fetchOtherCollections(completion: {
                    APIService.shared.postAuthorExcursion(callback: { [unowned self] result in
                        switch result {
                        case .failure(let error):
                            print(error.localizedDescription)
                            return
                        case .success(let personalExcursion):
                            self.personalExcursions.accept(personalExcursion)
                            self.personalExcursionsLocalVal = self.personalExcursions.value
                            self.fetchUserCollections()
                        }
                    })
                })
            }).disposed(by: disposeBag)
        
        viewWillAppear.asObservable()
            .subscribe(onNext: { [unowned self] in
                APIService.shared.postExcursionGetGuides(callback: { result in
                    switch result {
                    case .failure(let error):
                        print(error.localizedDescription)
                        return
                    case .success(let guides):
                        self.guides.accept(guides)
                    }
                })
            }).disposed(by: disposeBag)
        
        playButton.asObservable()
            .subscribe(onNext: { [unowned self] in
                let url = Bundle.main.url(forResource: "sample", withExtension: "mp4")!
                self.video.onNext((videoUrl: url, isFullScreen: true))
            })
            .disposed(by: disposeBag)
        
        cellPlayButton.asObservable()
            .subscribe(onNext: { [unowned self] guide in
                guard let url = URL(string: guide.video ?? "") else { return }
                self.video.onNext((videoUrl: url, isFullScreen: false))
            })
            .disposed(by: disposeBag)
    }
}

// MARK: - Get Collections
extension GuideViewModel {
    private func fetchOtherCollections(completion: (() -> Void)? = nil) {
        APIService.shared.getPlacesCollections(cityId: selectedCityId) { [unowned self] result in
            switch result {
            case .failure(let error):
                print(error.localizedDescription)
                return
            case .success(let collections):
                self.otherCollections.accept(collections)
                completion?()
            }
        }
    }
    
    private func fetchUserCollections() {
        guard let tripId = CurrentTrip.shared.current?.tripId else { return }
        
        APIService.shared.postGetUserCollections(tripId: tripId) { result in
            switch result {
            case .failure(let error):
                print(error.localizedDescription)
                return
            case .success(let ids):
                let userCollections = self.otherCollections.value.filter({ ids.contains($0.id) })
                
                /// Removing empty items of collection
                var userCollectionsAfterFilter = [Wish]()
                for indexX in 0 ..< self.personalExcursionsLocalVal.count {
                    for indexY in 0 ..< userCollections.count {
                        if userCollections[indexY].id != self.personalExcursionsLocalVal[indexX].collectionID {
                            continue
                        }
                        userCollectionsAfterFilter += [userCollections[indexY]]
                    }
                }
                
                guard userCollectionsAfterFilter != [] else { return self.otherCollections.accept([]) }
                userCollectionsAfterFilter[0].isSelected = true
                self.userCollections.accept(userCollectionsAfterFilter)
                self.selectedCollection.accept(userCollectionsAfterFilter[0])
                var otherCollections = self.otherCollections.value
                otherCollections.removeAll(where: { userCollections.contains($0) })
                
                /// Removing empty items of collection
                var otherCollectionsAfterFilter = [Wish]()
                for indexX in 0 ..< self.personalExcursionsLocalVal.count {
                    for indexY in 0 ..< otherCollections.count {
                        if otherCollections[indexY].id != self.personalExcursionsLocalVal[indexX].collectionID {
                            continue
                        }
                        otherCollectionsAfterFilter += [otherCollections[indexY]]
                    }
                }
                
                self.otherCollections.accept(otherCollectionsAfterFilter)
            }
        }
    }
}
