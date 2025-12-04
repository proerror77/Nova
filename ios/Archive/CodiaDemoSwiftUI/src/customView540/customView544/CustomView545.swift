//
//  CustomView545.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView545: View {
    @State public var image376Path: String = "image376_41857"
    @State public var text258Text: String = "Account_one (Primary)"
    @State public var image377Path: String = "image377_41859"
    @State public var image378Path: String = "image378_41863"
    @State public var text259Text: String = "Add an alias account (Anonymous)"
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CustomView546(
                image376Path: image376Path,
                text258Text: text258Text,
                image377Path: image377Path)
            CustomView548(
                image378Path: image378Path,
                text259Text: text259Text)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 300.06, alignment: .leading)
    }
}

struct CustomView545_Previews: PreviewProvider {
    static var previews: some View {
        CustomView545()
    }
}
