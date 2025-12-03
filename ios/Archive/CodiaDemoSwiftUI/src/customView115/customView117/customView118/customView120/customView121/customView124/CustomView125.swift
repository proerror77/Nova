//
//  CustomView125.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView125: View {
    @State public var image98Path: String = "image98_4547"
    @State public var text76Text: String = "Gain collection points"
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(image98Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 36, alignment: .topLeading)
            Text(text76Text)
                .foregroundColor(Color(red: 0.66, green: 0.66, blue: 0.66, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 13))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView125_Previews: PreviewProvider {
    static var previews: some View {
        CustomView125()
    }
}
