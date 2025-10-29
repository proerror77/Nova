//
//  CustomView82.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView82: View {
    @State public var text51Text: String = "Following"
    @State public var text52Text: String = "3021"
    @State public var text53Text: String = "Followers"
    @State public var text54Text: String = "3021"
    @State public var text55Text: String = "Likes"
    @State public var text56Text: String = "3021"
    @State public var image74Path: String = "image74_4445"
    @State public var image75Path: String = "image75_4446"
    var body: some View {
        HStack(alignment: .center, spacing: -17) {
            CustomView83(
                text51Text: text51Text,
                text52Text: text52Text)
                .frame(width: 139)
            CustomView84(
                text53Text: text53Text,
                text54Text: text54Text)
                .frame(width: 139)
            CustomView85(
                text55Text: text55Text,
                text56Text: text56Text)
                .frame(width: 139)
            Image(image74Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 1, height: 26, alignment: .topLeading)
            Image(image75Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 1, height: 26, alignment: .topLeading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomView82_Previews: PreviewProvider {
    static var previews: some View {
        CustomView82()
    }
}
