//
//  RileyLinkDevicesHeaderView.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import UIKit

public class RileyLinkDevicesHeaderView: UITableViewHeaderFooterView, IdentifiableClass {

    override public init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)

        setup()
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        setup()
    }

    public let spinner = UIActivityIndicatorView(style: .default)

    private func setup() {
        contentView.addSubview(spinner)
        spinner.startAnimating()
    }

    override public func layoutSubviews() {
        super.layoutSubviews()

        spinner.center.y = textLabel?.center.y ?? 0
        spinner.frame.origin.x = contentView.bounds.size.width - contentView.directionalLayoutMargins.trailing - spinner.frame.size.width
    }
}
