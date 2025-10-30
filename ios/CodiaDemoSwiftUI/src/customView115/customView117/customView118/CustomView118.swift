//
//  CustomView118.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView118: View {
    @State public var text73Text: String = "Received likes and collected "
    @State public var image97Path: String = "image97_4540"
    @State public var text74Text: String = "Number of posts"
    @State public var text75Text: String = "30"
    @State public var image98Path: String = "image98_4547"
    @State public var text76Text: String = "Gain collection points"
    @State public var text77Text: String = "479"
    @State public var image99Path: String = "image99_4554"
    @State public var text78Text: String = "Get the number of likes"
    @State public var text79Text: String = "61"
    @State public var text80Text: String = "OK"
    var body: some View {
        VStack(alignment: .center, spacing: 44) {
            CustomView119(text73Text: text73Text)
            CustomView120(
                image97Path: image97Path,
                text74Text: text74Text,
                text75Text: text75Text,
                image98Path: image98Path,
                text76Text: text76Text,
                text77Text: text77Text,
                image99Path: image99Path,
                text78Text: text78Text,
                text79Text: text79Text,
                text80Text: text80Text)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 216, alignment: .leading)
    }
}

struct CustomView118_Previews: PreviewProvider {
    static var previews: some View {
        CustomView118()
    }
}
