//
//  CustomView80.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView80: View {
    @State public var image73Path: String = "image73_4423"
    @State public var text49Text: String = "Bruce Li"
    @State public var text50Text: String = "China"
    @State public var text51Text: String = "Following"
    @State public var text52Text: String = "3021"
    @State public var text53Text: String = "Followers"
    @State public var text54Text: String = "3021"
    @State public var text55Text: String = "Likes"
    @State public var text56Text: String = "3021"
    @State public var image74Path: String = "image74_4445"
    @State public var image75Path: String = "image75_4446"
    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            CustomView81(
                image73Path: image73Path,
                text49Text: text49Text,
                text50Text: text50Text)
                .frame(width: 137)
            CustomView82(
                text51Text: text51Text,
                text52Text: text52Text,
                text53Text: text53Text,
                text54Text: text54Text,
                text55Text: text55Text,
                text56Text: text56Text,
                image74Path: image74Path,
                image75Path: image75Path)
        }
        .frame(width: 383, height: 263, alignment: .top)
    }
}

struct CustomView80_Previews: PreviewProvider {
    static var previews: some View {
        CustomView80()
    }
}
