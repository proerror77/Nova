//
//  CustomView121.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView121: View {
    @State public var image97Path: String = "image97_4540"
    @State public var text74Text: String = "Number of posts"
    @State public var text75Text: String = "30"
    @State public var image98Path: String = "image98_4547"
    @State public var text76Text: String = "Gain collection points"
    @State public var text77Text: String = "479"
    @State public var image99Path: String = "image99_4554"
    @State public var text78Text: String = "Get the number of likes"
    @State public var text79Text: String = "61"
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            CustomView122(
                image97Path: image97Path,
                text74Text: text74Text,
                text75Text: text75Text)
            CustomView124(
                image98Path: image98Path,
                text76Text: text76Text,
                text77Text: text77Text)
            CustomView126(
                image99Path: image99Path,
                text78Text: text78Text,
                text79Text: text79Text)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView121_Previews: PreviewProvider {
    static var previews: some View {
        CustomView121()
    }
}
