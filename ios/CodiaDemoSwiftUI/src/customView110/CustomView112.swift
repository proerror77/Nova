//
//  CustomView112.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView112: View {
    @State public var text71Text: String = "Bruce Li"
    @State public var image90Path: String = "image90_I451641875"
    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            Text(text71Text)
                .foregroundColor(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 21))
                .lineLimit(1)
                .frame(width: 83, alignment: .leading)
                .multilineTextAlignment(.leading)
            Image(image90Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 11, height: 5, alignment: .topLeading)
        }
        .frame(width: 100, height: 16, alignment: .top)
    }
}

struct CustomView112_Previews: PreviewProvider {
    static var previews: some View {
        CustomView112()
    }
}
