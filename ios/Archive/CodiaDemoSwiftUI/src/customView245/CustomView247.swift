//
//  CustomView247.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView247: View {
    @State public var text139Text: String = "Bruce Li"
    @State public var image179Path: String = "image179_I487241875"
    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            Text(text139Text)
                .foregroundColor(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 21))
                .lineLimit(1)
                .frame(width: 83, alignment: .leading)
                .multilineTextAlignment(.leading)
            Image(image179Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 11, height: 5, alignment: .topLeading)
        }
        .frame(width: 100, height: 16, alignment: .top)
    }
}

struct CustomView247_Previews: PreviewProvider {
    static var previews: some View {
        CustomView247()
    }
}
